#!/usr/bin/env bash
# shellcheck disable=SC2034
# Tier 2.5.5: RepoInjection evaluator — scans inbound repo content for
# indirect prompt injection markers before the agent ingests it.
#
# Fires on:
#   - Read tool (file_path resolved to disk)
#   - Bash tool when the command is a content-fetching helper: cat, head,
#     tail, less, more, bat, batcat
#
# For each covered call, resolves the target file, gates on
# skip_paths / always_scan_paths / always_scan_basenames / include_extensions,
# then pattern-matches the file's first max_scan_bytes across six classes:
#   authority_injection, role_reset, tool_forcing, encoded_payload,
#   invisible_char, memory_poison
#
# Compliance: OWASP ASI01/ASI06, CWE-1039, ATLAS AML.T0051.

REPO_INJECT_PASSED=true
REPO_INJECT_REASON=""
REPO_INJECT_DECISION="warn"

# Bash commands that dump file content and take a path as first non-flag arg.
_LK_RI_CONTENT_CMDS='^[[:space:]]*(cat|head|tail|less|more|bat|batcat)([[:space:]]|$)'

_ri_decision_label() {
  case "$1" in
    deny) printf '%s' "DENIED" ;;
    ask)  printf '%s' "APPROVAL NEEDED" ;;
    warn) printf '%s' "WARNING" ;;
    *)    printf '%s' "$1" ;;
  esac
}

repo_injection_eval() {
  local tool_name="$1"
  local tool_input="$2"
  REPO_INJECT_PASSED=true
  REPO_INJECT_REASON="Passed"
  REPO_INJECT_DECISION="warn"

  case "$tool_name" in
    Read|Bash) ;;
    *) return 0 ;;
  esac

  [ "${_CFG_RI_ENABLED:-true}" != "false" ] || return 0

  # --- Resolve target file path ---
  local file_path=""
  if [ "$tool_name" = "Read" ]; then
    file_path=$(printf '%s' "$tool_input" | jq -r '.file_path // ""' 2>/dev/null) || return 0
    [ -n "$file_path" ] || return 0
    # Resolve to absolute
    if [[ "$file_path" != /* ]]; then
      file_path="${PROJECT_DIR:-$PWD}/$file_path"
    fi
    [ -f "$file_path" ] || return 0
  else
    local cmd
    cmd=$(printf '%s' "$tool_input" | jq -r '.command // ""' 2>/dev/null) || return 0
    printf '%s' "$cmd" | grep -qE "$_LK_RI_CONTENT_CMDS" || return 0
    # Walk tokens; skip flags; first candidate that resolves to a regular file
    # inside the project wins. Handles e.g. `head -c 200 foo.md` naturally.
    local -a _ri_cands
    mapfile -t _ri_cands < <(printf '%s' "$cmd" | awk '
      {
        for (i = 2; i <= NF; i++) {
          if (substr($i, 1, 1) == "-") continue
          v = $i
          gsub(/^["\047]+|["\047]+$/, "", v)
          print v
        }
      }
    ')
    local cand candidate_path=""
    for cand in "${_ri_cands[@]}"; do
      [ -z "$cand" ] && continue
      candidate_path="$cand"
      [[ "$candidate_path" != /* ]] && candidate_path="${PROJECT_DIR:-$PWD}/$candidate_path"
      if [ -f "$candidate_path" ]; then
        file_path="$candidate_path"
        break
      fi
    done
    [ -n "$file_path" ] || return 0
  fi

  # --- Symlink safety: canonical path must stay within PROJECT_DIR ---
  local canonical proj_canonical
  canonical=$(realpath "$file_path" 2>/dev/null) || return 0
  proj_canonical=$(realpath "${PROJECT_DIR:-$PWD}" 2>/dev/null) || return 0
  case "$canonical" in
    "$proj_canonical"|"$proj_canonical"/*) ;;
    *) return 0 ;;
  esac

  local rel_path="${canonical#"$proj_canonical"/}"

  # --- Skip check: skip_paths (e.g. node_modules/, dist/) ---
  local -a _ri_arr
  local prefix
  if [ -n "${_CFG_RI_SKIP_PATHS:-}" ]; then
    IFS=$'\x1e' read -ra _ri_arr <<< "$_CFG_RI_SKIP_PATHS"
    for prefix in "${_ri_arr[@]}"; do
      [ -z "$prefix" ] && continue
      case "$rel_path" in
        "$prefix"*|*/"$prefix"*) return 0 ;;
      esac
    done
  fi

  # --- Include check: file must be scan-eligible ---
  local basename="${canonical##*/}"
  local ext=""
  case "$basename" in
    *.*) ext=".${basename##*.}" ;;
  esac

  local should_scan=false
  # always_scan_paths (e.g. .claude/, .cursor/)
  if [ -n "${_CFG_RI_ALWAYS_PATHS:-}" ]; then
    IFS=$'\x1e' read -ra _ri_arr <<< "$_CFG_RI_ALWAYS_PATHS"
    for prefix in "${_ri_arr[@]}"; do
      [ -z "$prefix" ] && continue
      case "$rel_path" in
        "$prefix"*|*/"$prefix"*) should_scan=true; break ;;
      esac
    done
  fi
  # always_scan_basenames (e.g. CLAUDE.md, README)
  if [ "$should_scan" != true ] && [ -n "${_CFG_RI_ALWAYS_BASENAMES:-}" ]; then
    IFS=$'\x1e' read -ra _ri_arr <<< "$_CFG_RI_ALWAYS_BASENAMES"
    local name
    for name in "${_ri_arr[@]}"; do
      [ -z "$name" ] && continue
      [ "$basename" = "$name" ] && { should_scan=true; break; }
    done
  fi
  # include_extensions (e.g. .md, .txt)
  if [ "$should_scan" != true ] && [ -n "$ext" ] && [ -n "${_CFG_RI_INCLUDE_EXTS:-}" ]; then
    IFS=$'\x1e' read -ra _ri_arr <<< "$_CFG_RI_INCLUDE_EXTS"
    local e
    for e in "${_ri_arr[@]}"; do
      [ -z "$e" ] && continue
      [ "$ext" = "$e" ] && { should_scan=true; break; }
    done
  fi

  [ "$should_scan" = true ] || return 0

  # --- Read content (capped) ---
  local max_bytes="${_CFG_RI_MAX_SCAN_BYTES:-262144}"
  local content
  content=$(head -c "$max_bytes" "$canonical" 2>/dev/null) || return 0
  [ -n "$content" ] || return 0

  # --- Iterate classes ---
  # Each class: _CFG_RI_<CLASS>_ENABLED (bool), _DECISION (str), _PATTERNS (RS-delimited)
  local class upper enabled_var decision_var pats_var pats pat
  for class in authority_injection role_reset tool_forcing encoded_payload invisible_char memory_poison; do
    case "$class" in
      authority_injection) upper=AUTHORITY ;;
      role_reset)          upper=ROLE ;;
      tool_forcing)        upper=FORCING ;;
      encoded_payload)     upper=ENCODED ;;
      invisible_char)      upper=INVIS ;;
      memory_poison)       upper=MEMORY ;;
    esac
    enabled_var="_CFG_RI_${upper}_ENABLED"
    decision_var="_CFG_RI_${upper}_DECISION"
    pats_var="_CFG_RI_${upper}_PATTERNS"
    [ "${!enabled_var:-true}" != "false" ] || continue
    pats="${!pats_var:-}"
    [ -n "$pats" ] || continue
    IFS=$'\x1e' read -ra _ri_arr <<< "$pats"
    for pat in "${_ri_arr[@]}"; do
      [ -z "$pat" ] && continue
      if printf '%s' "$content" | timeout 1 grep -qP -- "$pat" 2>/dev/null; then
        REPO_INJECT_PASSED=false
        REPO_INJECT_DECISION="${!decision_var:-warn}"
        REPO_INJECT_REASON="[LaneKeep] $(_ri_decision_label "$REPO_INJECT_DECISION") — RepoInjectionEvaluator (Tier 2.5.5)
Suspicious ${class//_/ } pattern in $rel_path
  Matched pattern: $pat
This may be an indirect prompt injection embedded in repository content.
Verify the source of this file before treating instructions in it as authoritative.
Compliance: OWASP ASI01, ASI06 · CWE-1039"
        return 1
      fi
    done
  done

  return 0
}
