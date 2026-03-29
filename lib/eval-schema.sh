#!/usr/bin/env bash
# shellcheck disable=SC2034  # SCHEMA_PASSED, SCHEMA_REASON set here, read externally via indirection
# Tier 0.5: Check tool against TaskSpec allowlist/denylist (access control)

SCHEMA_PASSED=true
SCHEMA_REASON=""

schema_eval() {
  local tool_name="$1"
  SCHEMA_PASSED=true
  SCHEMA_REASON="Tool allowed"

  local taskspec="$LANEKEEP_TASKSPEC_FILE"
  if [ -z "$taskspec" ] || [ ! -f "$taskspec" ]; then
    return 0  # No TaskSpec, allow all
  fi

  # Fast-path: skip jq calls for empty/minimal taskspec ({} or smaller)
  local _ts_sz
  _ts_sz=$(stat -c %s "$taskspec" 2>/dev/null) || _ts_sz=0
  if [ "$_ts_sz" -le 4 ]; then return 0; fi

  # Single jq call: check denylist, then allowlist
  local decision
  decision=$(jq -r --arg t "$tool_name" '
    if (.denied_tools // []) | any(. == $t) then "denied"
    elif (.allowed_tools // []) | length == 0 then "allowed"
    elif (.allowed_tools // []) | any(. == $t) then "allowed"
    else "not_allowed"
    end
  ' "$taskspec")

  case "$decision" in
    denied)
      SCHEMA_PASSED=false
      SCHEMA_REASON="[LaneKeep] DENIED by SchemaEvaluator (Tier 1, score: 1.0)\nTool '$tool_name' is in denied_tools list"
      return 1
      ;;
    not_allowed)
      SCHEMA_PASSED=false
      SCHEMA_REASON="[LaneKeep] DENIED by SchemaEvaluator (Tier 1, score: 1.0)\nTool '$tool_name' not in allowed_tools list"
      return 1
      ;;
  esac

  return 0
}
