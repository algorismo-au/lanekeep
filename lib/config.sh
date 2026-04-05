#!/usr/bin/env bash
# shellcheck disable=SC2034  # INTEGRITY_PASSED, INTEGRITY_REASON set here, read externally via indirection
# Config loader: resolves lanekeep.json, sets up session directories, parses TaskSpec

# M2: Validate security-critical env var overrides.
# Called early in load_config(). Invalid values are reset to defaults with a
# warning to stderr — never silently accepted.
validate_env_overrides() {
  local project_dir="$1"

  # LANEKEEP_FAIL_POLICY: must be deny|allow
  if [ -n "${LANEKEEP_FAIL_POLICY:-}" ]; then
    case "$LANEKEEP_FAIL_POLICY" in
      deny|allow) ;;
      *)
        echo "[LaneKeep] WARNING: Invalid LANEKEEP_FAIL_POLICY='$LANEKEEP_FAIL_POLICY' — must be 'deny' or 'allow'. Falling back to 'deny'." >&2
        LANEKEEP_FAIL_POLICY="deny"
        export LANEKEEP_FAIL_POLICY
        ;;
    esac
  fi

  # LANEKEEP_LICENSE_TIER: must be community|pro|enterprise
  if [ -n "${LANEKEEP_LICENSE_TIER:-}" ]; then
    case "$LANEKEEP_LICENSE_TIER" in
      community|pro|enterprise) ;;
      *)
        echo "[LaneKeep] WARNING: Invalid LANEKEEP_LICENSE_TIER='$LANEKEEP_LICENSE_TIER' — must be 'community', 'pro', or 'enterprise'. Falling back to 'community'." >&2
        LANEKEEP_LICENSE_TIER="community"
        export LANEKEEP_LICENSE_TIER
        ;;
    esac
  fi

  # LANEKEEP_CONFIG_FILE: must exist, be a regular file (not symlink), and
  # resolve within the project directory
  if [ -n "${LANEKEEP_CONFIG_FILE:-}" ]; then
    local _valid=true
    if [ -L "$LANEKEEP_CONFIG_FILE" ]; then
      echo "[LaneKeep] WARNING: LANEKEEP_CONFIG_FILE is a symlink — rejecting for security. Falling back to default." >&2
      _valid=false
    elif [ ! -f "$LANEKEEP_CONFIG_FILE" ]; then
      echo "[LaneKeep] WARNING: LANEKEEP_CONFIG_FILE='$LANEKEEP_CONFIG_FILE' does not exist or is not a regular file. Falling back to default." >&2
      _valid=false
    else
      # Resolve to absolute path and verify it's under project_dir
      local _resolved _proj_real
      _resolved=$(cd "$(dirname "$LANEKEEP_CONFIG_FILE")" && pwd -P)/$(basename "$LANEKEEP_CONFIG_FILE")
      _proj_real=$(cd "$project_dir" && pwd -P)
      case "$_resolved" in
        "$_proj_real"/*) ;;  # within project — ok
        *)
          echo "[LaneKeep] WARNING: LANEKEEP_CONFIG_FILE resolves outside project directory. Falling back to default." >&2
          _valid=false
          ;;
      esac
    fi
    if [ "$_valid" = "false" ]; then
      unset LANEKEEP_CONFIG_FILE
    fi
  fi

  # LANEKEEP_MAX_* vars: must be positive integers
  local _max_var
  for _max_var in \
    LANEKEEP_MAX_ACTIONS LANEKEEP_MAX_TOKENS LANEKEEP_MAX_INPUT_TOKENS \
    LANEKEEP_MAX_OUTPUT_TOKENS LANEKEEP_MAX_TOTAL_ACTIONS \
    LANEKEEP_MAX_TOTAL_INPUT_TOKENS LANEKEEP_MAX_TOTAL_OUTPUT_TOKENS \
    LANEKEEP_MAX_TOTAL_TOKENS LANEKEEP_MAX_TOTAL_TIME; do
    local _val="${!_max_var:-}"
    if [ -n "$_val" ]; then
      if ! [[ "$_val" =~ ^[1-9][0-9]*$ ]]; then
        echo "[LaneKeep] WARNING: Invalid $_max_var='$_val' — must be a positive integer. Ignoring override." >&2
        unset "$_max_var"
      fi
    fi
  done
}

load_config() {
  local project_dir="$1"
  local spec_file="${2:-}"

  # --- M2: Validate env overrides before any config resolution ---
  validate_env_overrides "$project_dir"

  # --- Resolve config file ---
  LANEKEEP_CONFIG_FILE="${LANEKEEP_CONFIG_FILE:-$project_dir/lanekeep.json}"
  # Fallback to .bak when primary config is missing
  if [ ! -f "$LANEKEEP_CONFIG_FILE" ] && [ -f "$project_dir/lanekeep.json.bak" ]; then
    LANEKEEP_CONFIG_FILE="$project_dir/lanekeep.json.bak"
  fi

  # Save user's explicit budget/evaluator values before resolve_config or
  # apply_profile can overwrite them.  Profile values are defaults — user's
  # explicit values take precedence.
  local _user_budget_override="{}" _user_evaluators_override="{}"
  if [ -f "$LANEKEEP_CONFIG_FILE" ]; then
    eval "$(jq -r '
      "_user_budget_override=" + (if has("budget") then .budget | tojson else "{}" end | @sh),
      "_user_evaluators_override=" + (if has("evaluators") then .evaluators | tojson else "{}" end | @sh)
    ' "$LANEKEEP_CONFIG_FILE" 2>/dev/null)" || true
  fi

  if [ ! -f "$LANEKEEP_CONFIG_FILE" ]; then
    (umask 077; mkdir -p "$project_dir/.lanekeep")
    cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$project_dir/.lanekeep/resolved-config.json"
    LANEKEEP_CONFIG_FILE="$project_dir/.lanekeep/resolved-config.json"
  fi

  # --- Config layering: merge user overrides with defaults ---
  resolve_config "$LANEKEEP_CONFIG_FILE" "$LANEKEEP_DIR/defaults/lanekeep.json"

  # --- Validate regex patterns at config load (warn-only) ---
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
  validate_patterns "$LANEKEEP_CONFIG_FILE" || true

  # --- Optional config signing verification ---
  if [ -f "$LANEKEEP_DIR/lib/signing.sh" ]; then
    source "$LANEKEEP_DIR/lib/signing.sh"
    local require_signed
    require_signed=$(jq -r '.signing.require_signed_config // false' "$LANEKEEP_CONFIG_FILE" 2>/dev/null) || require_signed="false"
    if [ "$require_signed" = "true" ]; then
      local pubkey_path
      pubkey_path=$(jq -r '.signing.pubkey_path // ""' "$LANEKEEP_CONFIG_FILE" 2>/dev/null) || pubkey_path=""
      if [ -n "$pubkey_path" ] && [ -f "$pubkey_path" ]; then
        local config_content
        config_content=$(cat "$LANEKEEP_CONFIG_FILE")
        verify_inline_sig "$config_content" "$pubkey_path"
        local sig_exit=$?
        if [ "$sig_exit" -eq 1 ]; then
          LANEKEEP_CONFIG_INVALID=1
          export LANEKEEP_CONFIG_INVALID
          echo "[LaneKeep] ERROR: Config signature verification failed — deny-all mode" >&2
        fi
      fi
    fi
  fi

  # --- Generate session ID ---
  LANEKEEP_SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"

  # --- Create directories ---
  (umask 077; mkdir -p "$project_dir/.lanekeep/traces")

  # --- Auto-prune old trace files (best-effort, non-blocking) ---
  source "$LANEKEEP_DIR/lib/trace.sh"
  local _trace_ret_days _trace_max_sess
  _trace_ret_days=$(jq -r '.trace.retention_days // 365' "$LANEKEEP_CONFIG_FILE" 2>/dev/null) || _trace_ret_days=365
  _trace_max_sess=$(jq -r '.trace.max_sessions // 100' "$LANEKEEP_CONFIG_FILE" 2>/dev/null) || _trace_max_sess=100
  prune_traces "$project_dir/.lanekeep/traces" "$_trace_ret_days" "$_trace_max_sess" true "${LANEKEEP_SESSION_ID:-}" || true

  # --- Parse TaskSpec if spec file provided ---
  LANEKEEP_TASKSPEC_FILE="$project_dir/.lanekeep/taskspec.json"
  if [ -n "$spec_file" ] && [ -f "$spec_file" ]; then
    if [ -x "$LANEKEEP_DIR/bin/lanekeep-parse-spec" ]; then
      "$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$spec_file" > "$LANEKEEP_TASKSPEC_FILE" 2>/dev/null || true
    fi
  fi

  # --- Set paths ---
  LANEKEEP_STATE_FILE="$project_dir/.lanekeep/state.json"
  LANEKEEP_TRACE_FILE="$project_dir/.lanekeep/traces/${LANEKEEP_SESSION_ID}.jsonl"
  LANEKEEP_CUMULATIVE_FILE="$project_dir/.lanekeep/cumulative.json"

  # --- Finalize previous session into cumulative stats ---
  source "$LANEKEEP_DIR/lib/cumulative.sh"
  cumulative_init

  # --- Initialize session state ---
  jq -n --argjson epoch "$(date +%s)" --arg sid "$LANEKEEP_SESSION_ID" \
    '{action_count: 0, token_count: 0, input_tokens: 0, output_tokens: 0, total_events: 0, start_epoch: $epoch, session_id: $sid, lanekeep_session_id: $sid}' > "$LANEKEEP_STATE_FILE"

  # --- Defaults version tracking: one-time notice on upgrade ---
  local _dv_file="$project_dir/.lanekeep/defaults_manifest.json"
  local _dv_current
  _dv_current=$(jq -r '.version // empty' "$LANEKEEP_DIR/defaults/lanekeep.json" 2>/dev/null) || _dv_current=""
  if [ -n "$_dv_current" ]; then
    if [ -f "$_dv_file" ]; then
      local _dv_last
      _dv_last=$(jq -r '.defaults_version // empty' "$_dv_file" 2>/dev/null) || _dv_last=""
      if [ -n "$_dv_last" ] && [ "$_dv_last" != "$_dv_current" ]; then
        local _dv_new_count
        _dv_new_count=$(jq -s --slurpfile manifest "$_dv_file" '
          .[0] as $defs |
          ($manifest[0].rule_ids // []) as $old_ids |
          [($defs.rules // [])[] | select(has("id")) | .id |
           select(. as $id | ($old_ids | index($id)) == null)] | length
        ' "$LANEKEEP_DIR/defaults/lanekeep.json" 2>/dev/null) || _dv_new_count="?"
        echo "[LaneKeep] Updated: v${_dv_last} → v${_dv_current} — ${_dv_new_count} new default rule(s) now active." >&2
        echo "[LaneKeep] Run 'lanekeep rules whatsnew' to review. Your customizations are preserved." >&2
        # Update version so this notice doesn't repeat for the same version bump
        local _dv_tmp; _dv_tmp=$(mktemp "${_dv_file}.XXXXXX")
        if jq --arg v "$_dv_current" '.defaults_version = $v' "$_dv_file" > "$_dv_tmp" 2>/dev/null; then
          mv "$_dv_tmp" "$_dv_file"
        else
          rm -f "$_dv_tmp"
        fi
      fi
    else
      # First run: create manifest silently (baseline for future comparisons)
      local _dv_ids
      _dv_ids=$(jq -c '[.rules[] | select(has("id")) | .id]' "$LANEKEEP_DIR/defaults/lanekeep.json" 2>/dev/null) || _dv_ids="[]"
      local _dv_tmp; _dv_tmp=$(mktemp "${_dv_file}.XXXXXX")
      if jq -n --arg v "$_dv_current" --argjson ids "$_dv_ids" \
        '{defaults_version: $v, rule_ids: $ids}' > "$_dv_tmp" 2>/dev/null; then
        mv "$_dv_tmp" "$_dv_file"
      else
        rm -f "$_dv_tmp"
      fi
    fi
  fi

  # --- Load platform-specific rule packs ---
  load_platform_pack "$LANEKEEP_CONFIG_FILE"

  # --- Load pro compliance tag overlays (gated on license tier) ---
  load_pro_packs "$LANEKEEP_CONFIG_FILE"

  # --- Load enterprise rules from ee/rules/ (gated on enterprise tier) ---
  load_enterprise_rules "$LANEKEEP_CONFIG_FILE"

  # --- Apply profile overlay if set ---
  apply_profile "$LANEKEEP_CONFIG_FILE"

  # Re-apply user's explicit budget/evaluator values over profile defaults
  if [ "$_user_budget_override" != "{}" ] || [ "$_user_evaluators_override" != "{}" ]; then
    local _reapplied
    _reapplied=$(jq --argjson ub "$_user_budget_override" --argjson ue "$_user_evaluators_override" '
      if ($ub | length) > 0 then .budget = ((.budget // {}) * $ub) else . end |
      if ($ue | length) > 0 then .evaluators = ((.evaluators // {}) * $ue) else . end
    ' "$LANEKEEP_CONFIG_FILE" 2>/dev/null) || true
    if [ -n "$_reapplied" ]; then
      local _tmp; _tmp=$(mktemp "${LANEKEEP_CONFIG_FILE}.XXXXXX")
      printf '%s\n' "$_reapplied" > "$_tmp" && mv "$_tmp" "$LANEKEEP_CONFIG_FILE"
    fi
  fi

  # --- Compute config hash for integrity checks ---
  LANEKEEP_CONFIG_HASH=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  LANEKEEP_CONFIG_HASH_FILE="$project_dir/.lanekeep/config_hash"
  # Atomic hash write: temp file + rename (M4 fix)
  local _hash_tmp
  _hash_tmp=$(mktemp "${LANEKEEP_CONFIG_HASH_FILE}.XXXXXX")
  (umask 077; printf '%s\n' "$LANEKEEP_CONFIG_HASH" > "$_hash_tmp")
  chmod 600 "$_hash_tmp"
  mv "$_hash_tmp" "$LANEKEEP_CONFIG_HASH_FILE"
  export LANEKEEP_CONFIG_HASH LANEKEEP_CONFIG_HASH_FILE

  # --- Export ---
  export LANEKEEP_ENV="${LANEKEEP_ENV:-}"
  export LANEKEEP_DIR PROJECT_DIR LANEKEEP_CONFIG_FILE LANEKEEP_SESSION_ID
  export LANEKEEP_TASKSPEC_FILE LANEKEEP_STATE_FILE LANEKEEP_TRACE_FILE LANEKEEP_CUMULATIVE_FILE
}

resolve_config() {
  local user_config="$1"
  local defaults="$2"

  [ -f "$user_config" ] || return 0
  [ -f "$defaults" ] || return 0

  # Check if user config extends defaults
  local extends
  extends=$(jq -r '.extends // empty' "$user_config" 2>/dev/null) || return 0
  [ "$extends" = "defaults" ] || return 0

  # M3: Log warnings for any rule_overrides targeting locked/sys rules
  local _locked_warnings
  _locked_warnings=$(jq -r --slurpfile defs "$defaults" '
    .rule_overrides // [] | .[] |
    .id as $oid |
    ($defs[0].rules // [] | map(select(.id == $oid)) | first // null) as $drule |
    if $drule != null and (($drule.locked == true) or ($oid | test("^sys-[0-9]+$"))) then
      "[LaneKeep] WARNING: rule_overrides for locked rule \"\($oid)\" ignored — security-critical rules cannot be overridden"
    else empty end
  ' "$user_config" 2>/dev/null) || _locked_warnings=""
  if [ -n "$_locked_warnings" ]; then
    echo "$_locked_warnings" >&2
  fi

  # Merge: defaults as base, user overrides on top
  # Special fields: rule_overrides (patch by id), extra_rules (append),
  # disabled_rules (remove by id)
  local merged
  merged=$(jq -s --arg defaults_path "$defaults" '
    .[0] as $defaults | .[1] as $user |

    # Deep merge objects (user wins on conflicts)
    def deep_merge(a; b):
      a as $a | b as $b |
      if ($a | type) == "object" and ($b | type) == "object" then
        ($a | keys) + ($b | keys) | unique | map(
          . as $k |
          if $k == "rules" or $k == "rule_overrides" or $k == "extra_rules" or $k == "disabled_rules" or $k == "extends" then
            null  # handled separately
          elif ($b | has($k)) and ($a | has($k)) then
            {($k): deep_merge($a[$k]; $b[$k])}
          elif ($b | has($k)) then
            {($k): $b[$k]}
          else
            {($k): $a[$k]}
          end
        ) | map(select(. != null)) | add // {}
      else $b end;

    # Start with deep-merged base (non-rules fields)
    deep_merge($defaults; $user) |

    # Rules: start with defaults, apply overrides, add extras, remove disabled
    .rules = (
      ($defaults.rules // []) |

      # Apply rule_overrides by id (M3: skip locked rules)
      if ($user.rule_overrides | length) > 0 then
        map(
          . as $rule |
          if ($rule | has("id")) then
            ($user.rule_overrides | map(select(.id == $rule.id)) | first // null) as $override |
            if $override != null then
              # M3: Security-critical rules with locked=true or sys-0xx IDs cannot be overridden
              if ($rule.locked == true) or ($rule.id | test("^sys-[0-9]+$")) then
                $rule
              else
                ($rule * $override)
              end
            else $rule end
          else $rule end
        )
      else . end |

      # Remove disabled_rules by id (M3: skip locked/sys rules)
      if ($user.disabled_rules | length) > 0 then
        map(select(
          if has("id") then
            .id as $rid |
            if (.locked == true) or ($rid | test("^sys-[0-9]+$")) then true
            else ($user.disabled_rules | map(select(. == $rid)) | length == 0) end
          else true end
        ))
      else . end
    ) +
    # Append extra_rules, tagged as custom source
    (($user.extra_rules // []) | map(. + {"source": "custom"})) |

    # Remove layering-only fields from output
    del(.extends, .rule_overrides, .extra_rules, .disabled_rules)
  ' "$defaults" "$user_config" 2>/dev/null)

  if [ -n "$merged" ]; then
    # Write resolved config to a temp file (don't modify user's lanekeep.json)
    local resolved="$PROJECT_DIR/.lanekeep/resolved-config.json"
    printf '%s\n' "$merged" > "$resolved"
    LANEKEEP_CONFIG_FILE="$resolved"
  fi
}

load_platform_pack() {
  local config="$1"
  [ -f "$config" ] || return 0

  # Detect platform from $OSTYPE (bash built-in, no subprocess)
  local platform=""
  case "${OSTYPE:-}" in
    msys*|cygwin*|mingw*) platform="windows" ;;
  esac
  [ -n "$platform" ] || return 0

  local pack_file="$LANEKEEP_DIR/defaults/packs/${platform}.json"
  [ -f "$pack_file" ] || return 0

  # Merge pack rules into config (appended after core rules)
  local merged
  merged=$(jq --slurpfile pack "$pack_file" '
    .rules = (.rules // []) + ($pack[0].rules // [])
  ' "$config" 2>/dev/null) || return 0

  local _tmp; _tmp=$(mktemp "${config}.XXXXXX")
  printf '%s\n' "$merged" > "$_tmp" && mv "$_tmp" "$config"
}

# Load pro compliance tag overlays — merges compliance_tags from each pack's
# overlay.json onto matching rules by rule_id. Tags are additive (pro tags
# append on top of free-tier tags already baked into the rule). Gated on
# LANEKEEP_LICENSE_TIER=pro|enterprise.
#
# Requires verify_pack_rules() from eval-rules.sh, which is sourced before
# this function is called in load_config() (at eval-rules.sh source line).
load_pro_packs() {
  local config="$1"
  [ -f "$config" ] || return 0

  # Only active for pro or enterprise tiers
  case "${LANEKEEP_LICENSE_TIER:-community}" in
    pro|enterprise) ;;
    *) return 0 ;;
  esac

  # Locate the pro packs directory; LANEKEEP_PRO_DIR allows non-standard installs
  local pro_dir="${LANEKEEP_PRO_DIR:-$(dirname "${LANEKEEP_DIR:-}")/lanekeep-pro}"
  local packs_dir="${pro_dir}/packs"
  [ -d "$packs_dir" ] || return 0

  local pack_dir overlay_file
  for pack_dir in "$packs_dir"/*/; do
    overlay_file="${pack_dir}overlay.json"
    [ -f "$overlay_file" ] || continue

    # Verify pack signature (free-tier packs pass without check)
    if ! verify_pack_rules "$overlay_file" 2>/dev/null; then
      echo "[LaneKeep] WARNING: Pro pack signature invalid for '$(basename "$pack_dir")' — skipping" >&2
      continue
    fi

    # Merge: for each overlay entry, find the matching rule by rule_id and
    # append its compliance_tags (additive — never removes existing tags)
    local merged
    merged=$(jq --slurpfile overlay "$overlay_file" '
      ($overlay[0].overlays // []) as $ovl |
      .rules = [.rules[] |
        . as $rule |
        ([$ovl[] | select(.rule_id == $rule.id)] | first) as $match |
        if $match then
          .compliance_tags = ((.compliance_tags // []) + ($match.compliance_tags // []) | unique)
        else . end
      ]
    ' "$config" 2>/dev/null) || continue

    [ -n "$merged" ] || continue
    local _tmp; _tmp=$(mktemp "${config}.XXXXXX")
    printf '%s\n' "$merged" > "$_tmp" && mv "$_tmp" "$config"
  done
}

# load_enterprise_rules — merge enterprise rule files from ee/rules/ into the
# resolved config. Gated strictly on LANEKEEP_LICENSE_TIER=enterprise.
# Rule files must contain {"tier": "enterprise", "rules": [...]} and carry a
# valid Ed25519 _signature (same scheme as Pro packs via verify_pack_rules).
# Silently no-ops when ee/rules/ is empty (public scaffold state).
load_enterprise_rules() {
  local config="$1"
  [ -f "$config" ] || return 0

  [ "${LANEKEEP_LICENSE_TIER:-community}" = "enterprise" ] || return 0

  local ee_rules_dir="${LANEKEEP_DIR}/ee/rules"
  [ -d "$ee_rules_dir" ] || return 0

  local rules_file
  for rules_file in "$ee_rules_dir"/*.json; do
    [ -f "$rules_file" ] || continue

    # Verify Ed25519 signature — enterprise rules must be signed
    if ! verify_pack_rules "$rules_file" 2>/dev/null; then
      echo "[LaneKeep] WARNING: Enterprise rule file signature invalid for '$(basename "$rules_file")' — skipping" >&2
      continue
    fi

    # Merge .rules[] from enterprise file into the resolved config's rules array
    local merged
    merged=$(jq --slurpfile ent "$rules_file" '
      .rules = (.rules + ($ent[0].rules // []))
    ' "$config" 2>/dev/null) || continue

    [ -n "$merged" ] || continue
    local _tmp; _tmp=$(mktemp "${config}.XXXXXX")
    printf '%s\n' "$merged" > "$_tmp" && mv "$_tmp" "$config"
  done
}

apply_profile() {
  local config="$1"
  [ -f "$config" ] || return 0

  # Profile from env var takes precedence over config file
  local profile="${LANEKEEP_PROFILE:-}"
  if [ -z "$profile" ]; then
    profile=$(jq -r '.profile // empty' "$config" 2>/dev/null) || return 0
  fi
  [ -n "$profile" ] || return 0

  local overlay=""
  case "$profile" in
    strict)
      # No Bash, all writes ask, tight budget
      overlay='{
        "budget": {"max_actions": 50, "timeout_seconds": 900}
      }'
      # Prepend deny-Bash and ask-Write rules (first-match-wins)
      local strict_rules='[
        {"id":"profile-001","match":{"tool":"^Bash$"},"decision":"deny","reason":"Bash disabled in strict profile","category":"profile","intent":"Strict mode disables shell access to minimize blast radius","type":"free"},
        {"id":"profile-002","match":{"tool":"^(Write|Edit)$"},"decision":"ask","reason":"Write requires approval in strict profile","category":"profile","intent":"Strict mode requires human approval for all file mutations","type":"free"}
      ]'
      # Prepend strict rules before existing rules
      local prepended
      prepended=$(jq --argjson sr "$strict_rules" '.rules = ($sr + ((.rules // []) | map(select(.category != "profile"))))' "$config" 2>/dev/null) || return 0
      local _tmp; _tmp=$(mktemp "${config}.XXXXXX")
      printf '%s\n' "$prepended" > "$_tmp" && mv "$_tmp" "$config"
      ;;
    guided)
      # Network needs approval, push needs approval, moderate budget
      overlay='{
        "budget": {"max_actions": 200, "timeout_seconds": 3600}
      }'
      # Prepend ask-push rule
      local guided_rules='[
        {"id":"profile-001","match":{"command":"git push"},"decision":"ask","reason":"Push requires approval in guided profile","category":"profile","intent":"Guided mode requires human approval before pushing to remote","type":"free"}
      ]'
      local prepended
      prepended=$(jq --argjson gr "$guided_rules" '.rules = ($gr + ((.rules // []) | map(select(.category != "profile"))))' "$config" 2>/dev/null) || return 0
      local _tmp; _tmp=$(mktemp "${config}.XXXXXX")
      printf '%s\n' "$prepended" > "$_tmp" && mv "$_tmp" "$config"
      ;;
    autonomous)
      # Budget + trace only, permissive evaluators
      overlay='{
        "budget": {"max_actions": 500, "timeout_seconds": 7200},
        "evaluators": {
          "codediff": {"enabled": true},
          "semantic": {"enabled": false}
        }
      }'
      ;;
    *)
      echo "[LaneKeep] WARNING: Unknown profile '$profile', ignoring (valid: strict, guided, autonomous)" >&2
      return 0
      ;;
  esac

  # Merge overlay into config (overlay wins on conflicts)
  local merged
  merged=$(jq --argjson overlay "$overlay" '
    # Deep merge: overlay values win, arrays from overlay replace
    def deep_merge(a; b):
      a as $a | b as $b |
      if ($a | type) == "object" and ($b | type) == "object" then
        ($a | keys) + ($b | keys) | unique | map(
          . as $k |
          if ($b | has($k)) and ($a | has($k)) then
            {($k): deep_merge($a[$k]; $b[$k])}
          elif ($b | has($k)) then
            {($k): $b[$k]}
          else
            {($k): $a[$k]}
          end
        ) | add // {}
      else $b end;
    deep_merge(.; $overlay) | .profile = $prof
  ' --arg prof "$profile" "$config" 2>/dev/null) || return 0

  local _tmp; _tmp=$(mktemp "${config}.XXXXXX")
  printf '%s\n' "$merged" > "$_tmp" && mv "$_tmp" "$config"
}

verify_config_integrity() {
  # Resolve authorized hash: hash file (updated by UI saves) > env var (startup)
  local authorized_hash=""
  if [ -n "${LANEKEEP_CONFIG_HASH_FILE:-}" ] && [ -e "$LANEKEEP_CONFIG_HASH_FILE" ]; then
    # P2: Reject symlinks — attacker could point to a controlled file
    if [ -L "$LANEKEEP_CONFIG_HASH_FILE" ]; then
      INTEGRITY_PASSED=false
      INTEGRITY_REASON="[LaneKeep] DENIED: Config hash file is a symlink — possible tampering"
      return 1
    fi
    # Fast-path: if config is not newer than hash file, skip sha256sum (0 subprocesses)
    if [ ! "$LANEKEEP_CONFIG_FILE" -nt "$LANEKEEP_CONFIG_HASH_FILE" ]; then
      INTEGRITY_PASSED=true; INTEGRITY_REASON=""; return 0
    fi
    authorized_hash=$(head -1 "$LANEKEEP_CONFIG_HASH_FILE" 2>/dev/null) || authorized_hash=""
    # P1: Validate SHA-256 format — exactly 64 lowercase hex chars (bash builtin, no subprocess)
    if [ -n "$authorized_hash" ] && [[ ! "$authorized_hash" =~ ^[a-f0-9]{64}$ ]]; then
      INTEGRITY_PASSED=false
      INTEGRITY_REASON="[LaneKeep] DENIED: Config hash file contains invalid format — expected SHA-256"
      return 1
    fi
  fi
  [ -n "$authorized_hash" ] || authorized_hash="${LANEKEEP_CONFIG_HASH:-}"
  [ -n "$authorized_hash" ] || return 0
  [ -f "$LANEKEEP_CONFIG_FILE" ] || return 0
  # Verify SHA-256 (only reached when config is newer than hash file)
  local current_hash
  current_hash=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  if [ "$current_hash" != "$authorized_hash" ]; then
    INTEGRITY_PASSED=false
    INTEGRITY_REASON="[LaneKeep] DENIED: Config integrity check failed — lanekeep.json modified since session start"
    return 1
  fi
  INTEGRITY_PASSED=true
  INTEGRITY_REASON=""
  return 0
}
