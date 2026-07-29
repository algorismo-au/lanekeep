#!/usr/bin/env bash
# shellcheck disable=SC2034  # SCHEMA_PASSED, SCHEMA_REASON set here, read externally via indirection
# Tier 0.5: Check tool against config + TaskSpec allow/deny lists (access control)

SCHEMA_PASSED=true
SCHEMA_REASON=""

# Layering (later fails wins, i.e. any deny anywhere wins):
#   1. Config `denied_tools` (baseline, all sessions)
#   2. TaskSpec `denied_tools` (per-task)
#   3. Config `allowed_tools`  (baseline allow-list; empty/null = no restriction)
#   4. TaskSpec `allowed_tools` (narrows further; empty/null = no restriction)
# Both allow-lists apply as intersection when both are non-empty — a tool must
# satisfy every non-empty allow-list to reach ALLOW. Config denies are always
# enforced; a TaskSpec cannot re-enable a tool the config has denied.
schema_eval() {
  local tool_name="$1"
  SCHEMA_PASSED=true
  SCHEMA_REASON="Tool allowed"

  # --- Layer 1/3: config-level lists ---
  local cfg="${LANEKEEP_CONFIG_FILE:-}"
  local _cfg_out cfg_denied="" cfg_allow_len="0" cfg_in_allow="false"
  if [ -n "$cfg" ] && [ -f "$cfg" ]; then
    _cfg_out=$(jq -r --arg t "$tool_name" '
      ((if (.denied_tools // []) | any(. == $t) then "1" else "0" end) + "|" +
       ((.allowed_tools // []) | length | tostring) + "|" +
       (if (.allowed_tools // []) | any(. == $t) then "1" else "0" end))
    ' "$cfg" 2>/dev/null) || _cfg_out="0|0|0"
    cfg_denied="${_cfg_out%%|*}"
    local _rest="${_cfg_out#*|}"
    cfg_allow_len="${_rest%%|*}"
    cfg_in_allow="${_rest##*|}"
    if [ "$cfg_denied" = "1" ]; then
      SCHEMA_PASSED=false
      SCHEMA_REASON="[LaneKeep] DENIED by SchemaEvaluator (Tier 1, score: 1.0)\nTool '$tool_name' is in denied_tools list (config)"
      return 1
    fi
  fi

  # --- Layer 2/4: TaskSpec lists (also carries task_id side-effect) ---
  local taskspec="$LANEKEEP_TASKSPEC_FILE"
  local ts_denied="0" ts_allow_len="0" ts_in_allow="0" _ts_task=""
  if [ -n "$taskspec" ] && [ -f "$taskspec" ]; then
    # Fast-path: skip jq calls for empty/minimal taskspec ({} or smaller)
    local _ts_sz
    _ts_sz=$(stat -c %s "$taskspec" 2>/dev/null) || _ts_sz=0
    if [ "$_ts_sz" -gt 4 ]; then
      local _ts_out
      _ts_out=$(jq -r --arg t "$tool_name" '
        ((if (.denied_tools // []) | any(. == $t) then "1" else "0" end) + "|" +
         ((.allowed_tools // []) | length | tostring) + "|" +
         (if (.allowed_tools // []) | any(. == $t) then "1" else "0" end) + "|" +
         (.task_id // ""))
      ' "$taskspec" 2>/dev/null) || _ts_out="0|0|0|"
      ts_denied="${_ts_out%%|*}"
      local _r1="${_ts_out#*|}"
      ts_allow_len="${_r1%%|*}"
      local _r2="${_r1#*|}"
      ts_in_allow="${_r2%%|*}"
      _ts_task="${_r2#*|}"
    fi
  fi

  # Env wins; only fill in from TaskSpec when caller hasn't set it.
  if [ -n "$_ts_task" ] && [ -z "${LANEKEEP_TASK_ID:-}" ]; then
    export LANEKEEP_TASK_ID="$_ts_task"
  fi

  if [ "$ts_denied" = "1" ]; then
    SCHEMA_PASSED=false
    SCHEMA_REASON="[LaneKeep] DENIED by SchemaEvaluator (Tier 1, score: 1.0)\nTool '$tool_name' is in denied_tools list (TaskSpec)"
    return 1
  fi

  # Allow-list checks: each non-empty layer must include the tool.
  if [ "$cfg_allow_len" -gt 0 ] && [ "$cfg_in_allow" != "1" ]; then
    SCHEMA_PASSED=false
    SCHEMA_REASON="[LaneKeep] DENIED by SchemaEvaluator (Tier 1, score: 1.0)\nTool '$tool_name' not in allowed_tools list (config)"
    return 1
  fi
  if [ "$ts_allow_len" -gt 0 ] && [ "$ts_in_allow" != "1" ]; then
    SCHEMA_PASSED=false
    SCHEMA_REASON="[LaneKeep] DENIED by SchemaEvaluator (Tier 1, score: 1.0)\nTool '$tool_name' not in allowed_tools list (TaskSpec)"
    return 1
  fi

  return 0
}
