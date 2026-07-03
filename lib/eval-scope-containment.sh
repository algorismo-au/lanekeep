#!/usr/bin/env bash
# shellcheck disable=SC2034
# Tier 0.6: Scope containment — enforce allowed_paths from TaskSpec.
#
# When a TaskSpec sets .allowed_paths, this evaluator denies operations
# targeting files outside that scope. Covers:
#
#   Write / Edit — target = tool_input.file_path
#   Bash         — target = path-shaped args of destructive commands
#                  (rm, rmdir, mv, truncate, dd, shred, wipe, and
#                  find … -delete / find … -exec rm)
#
# Rationale: agents that find issues outside their scope should open a
# bug, not silently fix inline. This makes that discipline structural
# rather than disciplinary — the marquee agentic-coding incidents of 2026
# (PocketOS DB wipe, Claude C:\ deletion, Cowork family-photo delete) all
# shared the pattern of an agent operating far outside its intended blast
# radius.
#
# Opt-in: no allowed_paths → no enforcement. Ships enabled by default so
# TaskSpec-authored allowed_paths take effect immediately.
#
# Compliance: OWASP-ASI02 (Tool Misuse) / CWE-73 (Path Traversal).

SCOPE_PASSED=true
SCOPE_REASON=""
SCOPE_DECISION="deny"

# Bash commands whose remaining path-shaped args are treated as targets.
_LK_SCOPE_DESTRUCTIVE='^[[:space:]]*(rm|rmdir|mv|truncate|dd|shred|wipe|unlink)([[:space:]]|$)'
# `find <path> … -delete` or `find <path> … -exec rm …` — the leading
# non-flag args before the first `-…` flag are search roots.
_LK_SCOPE_FIND_DELETE='(^|[[:space:]|;&])find[[:space:]].*(-delete|-exec[[:space:]]+rm)'

_sc_decision_label() {
  case "$1" in
    deny) printf '%s' "DENIED" ;;
    ask)  printf '%s' "APPROVAL NEEDED" ;;
    warn) printf '%s' "WARNING" ;;
    *)    printf '%s' "$1" ;;
  esac
}

# Normalise a raw path argument: strip surrounding quotes, resolve
# relative-to-PROJECT_DIR, collapse `./` and `../` and duplicate slashes.
# Collapsing `../` is required — otherwise `src/../etc/hosts` would
# spuriously satisfy an `src/`-prefix rule.
_sc_normalise() {
  local raw="$1"
  # Strip a single layer of surrounding quotes.
  raw="${raw#[\"\']}"
  raw="${raw%[\"\']}"
  if [[ "$raw" != /* && "$raw" != ~* ]]; then
    raw="${PROJECT_DIR:-$PWD}/$raw"
  fi
  # ~ expansion (best-effort — bash-only)
  raw="${raw/#\~/$HOME}"
  # Collapse `./` and `//` mid-path.
  raw="${raw//\/.\//\/}"
  raw="${raw//\/\//\/}"
  # Collapse `<seg>/../` iteratively. Regex targets any segment (no `/`
  # inside it, not `..` itself) followed by `/..` — swap for empty.
  local before
  while [[ "$raw" == *"/../"* ]]; do
    before="$raw"
    raw=$(printf '%s' "$raw" | sed -E 's#/[^/]+/\.\./#/#g')
    [ "$before" = "$raw" ] && break   # no more collapse possible (e.g. leading /../)
  done
  # Handle trailing `/..` (no trailing slash) — one pass suffices.
  while [[ "$raw" == */../.. || "$raw" == */.. ]]; do
    before="$raw"
    raw=$(printf '%s' "$raw" | sed -E 's#/[^/]+/\.\.$##')
    [ "$before" = "$raw" ] && break
  done
  # Strip trailing slash for canonical form (except for root "/").
  if [ "$raw" != "/" ]; then
    raw="${raw%/}"
  fi
  printf '%s' "$raw"
}

scope_containment_eval() {
  local tool_name="$1"
  local tool_input="$2"
  SCOPE_PASSED=true
  SCOPE_REASON="Passed"
  SCOPE_DECISION="deny"

  case "$tool_name" in
    Write|Edit|Bash) ;;
    *) return 0 ;;
  esac

  [ "${_CFG_SCOPE_ENABLED:-true}" != "false" ] || return 0

  # --- Load allowed_paths (env override first, then TaskSpec, then jq fallback) ---
  local allowed_paths_rs="${_CFG_SCOPE_ALLOWED_PATHS:-}"
  if [ -z "$allowed_paths_rs" ] && [ -n "${LANEKEEP_TASKSPEC_FILE:-}" ] \
      && [ -f "$LANEKEEP_TASKSPEC_FILE" ]; then
    allowed_paths_rs=$(jq -r '(.allowed_paths // []) | join("")' \
      "$LANEKEEP_TASKSPEC_FILE" 2>/dev/null) || allowed_paths_rs=""
  fi
  # Opt-in: no allowed_paths declared → no enforcement.
  [ -n "$allowed_paths_rs" ] || return 0

  local -a _sc_allowed
  IFS=$'\x1e' read -ra _sc_allowed <<< "$allowed_paths_rs"

  # --- Collect target paths from the tool call ---
  local -a _sc_targets=()
  case "$tool_name" in
    Write|Edit)
      local fp
      fp=$(printf '%s' "$tool_input" | jq -r '.file_path // ""' 2>/dev/null) || fp=""
      [ -n "$fp" ] && _sc_targets+=("$fp")
      ;;
    Bash)
      local cmd
      cmd=$(printf '%s' "$tool_input" | jq -r '.command // ""' 2>/dev/null) || cmd=""
      [ -n "$cmd" ] || return 0

      local first_arg_only=false is_find=false
      if printf '%s' "$cmd" | grep -qE "$_LK_SCOPE_DESTRUCTIVE"; then
        : # collect all non-flag args
      elif printf '%s' "$cmd" | grep -qE "$_LK_SCOPE_FIND_DELETE"; then
        is_find=true
        first_arg_only=true
      else
        return 0
      fi

      # Extract candidate path args.
      if [ "$is_find" = true ]; then
        # find <root> [<root2> …] -flag … — take non-flag tokens until
        # first -flag.
        mapfile -t _sc_targets < <(printf '%s' "$cmd" | awk '{
          # Find the token "find" first, then take non-flag tokens after it.
          started = 0
          for (i = 1; i <= NF; i++) {
            if (!started) {
              if ($i == "find") { started = 1 }
              continue
            }
            if (substr($i, 1, 1) == "-") break
            v = $i; gsub(/^["\047]+|["\047]+$/, "", v)
            print v
          }
        }')
      else
        # rm / mv / truncate … — non-flag args are targets.
        mapfile -t _sc_targets < <(printf '%s' "$cmd" | awk '{
          for (i = 2; i <= NF; i++) {
            if (substr($i, 1, 1) == "-") continue
            v = $i; gsub(/^["\047]+|["\047]+$/, "", v)
            print v
          }
        }')
      fi
      # Suppress single-arg lint noise; first_arg_only is reserved for
      # future extensions that want per-command extraction semantics.
      : "$first_arg_only"
      ;;
  esac

  [ "${#_sc_targets[@]}" -gt 0 ] || return 0

  # --- Enforce scope ---
  local target norm allowed allowed_norm allowed_prefix matched
  for target in "${_sc_targets[@]}"; do
    [ -z "$target" ] && continue
    norm=$(_sc_normalise "$target")

    matched=false
    for allowed in "${_sc_allowed[@]}"; do
      [ -z "$allowed" ] && continue
      allowed_norm=$(_sc_normalise "$allowed")
      if [ "$norm" = "$allowed_norm" ]; then
        matched=true; break
      fi
      # Prefix: target must start with `allowed_norm/`. _sc_normalise
      # strips trailing slashes, so append one here for the compare.
      allowed_prefix="${allowed_norm}/"
      if [[ "$norm" == "$allowed_prefix"* ]]; then
        matched=true; break
      fi
    done

    if [ "$matched" = false ]; then
      SCOPE_PASSED=false
      SCOPE_DECISION="${_CFG_SCOPE_DECISION:-deny}"
      local allowed_list
      allowed_list=$(printf '%s, ' "${_sc_allowed[@]}" | sed 's/, $//')
      SCOPE_REASON="[LaneKeep] $(_sc_decision_label "$SCOPE_DECISION") — ScopeContainmentEvaluator (Tier 0.6)
Target path outside declared scope: $target
Tool: $tool_name
Declared allowed_paths: $allowed_list

Agents that find issues outside their scope should open a bug, not
silently fix inline. Re-scope the task or update allowed_paths in the
TaskSpec if this operation is legitimately in scope.

Compliance: OWASP-ASI02 (Tool Misuse), CWE-73 (Path Traversal)"
      return 1
    fi
  done

  return 0
}
