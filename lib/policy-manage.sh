#!/usr/bin/env bash
# Policy and rule management: disable/enable with audit trail

# _pm_policy_toggle CATEGORY ACTION USER REASON
# ACTION: "enable" | "disable"
# Validates the category exists, mutates .policies[CATEGORY].enabled atomically,
# then emits the audit event via write_policy_event.
_pm_policy_toggle() {
  local category="$1" action="$2" user="$3" reason="$4"
  local config="$LANEKEEP_CONFIG_FILE"

  [ -f "$config" ] || { echo "Config not found: $config" >&2; return 1; }

  local exists
  exists=$(jq --arg cat "$category" 'has("policies") and (.policies | has($cat))' "$config" 2>/dev/null)
  [ "$exists" = "true" ] || { echo "Policy category not found: $category" >&2; return 1; }

  local type
  type=$(jq -r --arg cat "$category" '.policies[$cat].type // "free"' "$config" 2>/dev/null)

  local filter event
  case "$action" in
    disable) filter='.policies[$cat].enabled = false'; event="policy_disabled" ;;
    enable)  filter='.policies[$cat] |= del(.enabled)'; event="policy_enabled" ;;
    *) echo "_pm_policy_toggle: unknown action: $action" >&2; return 1 ;;
  esac

  local tmp
  tmp=$(mktemp "${config}.tmp.XXXXXX")
  if jq --arg cat "$category" "$filter" "$config" > "$tmp"; then
    mv "$tmp" "$config"
  else
    rm -f "$tmp"; return 1
  fi

  write_policy_event "$event" "$category" "$type" "$user" "$reason"
}

# _pm_rule_toggle INDEX ACTION USER REASON
# ACTION: "enable" | "disable"
# Validates the index is in range for .rules, mutates .rules[INDEX].enabled
# atomically, then emits the audit event via write_rule_event.
_pm_rule_toggle() {
  local index="$1" action="$2" user="$3" reason="$4"
  local config="$LANEKEEP_CONFIG_FILE"

  [ -f "$config" ] || { echo "Config not found: $config" >&2; return 1; }

  local count
  count=$(jq '.rules | length' "$config" 2>/dev/null)
  if ! { [ "$index" -ge 0 ] && [ "$index" -lt "$count" ]; } 2>/dev/null; then
    echo "Rule index out of range: $index (have $count rules)" >&2; return 1
  fi

  local type
  type=$(jq -r --argjson idx "$index" '.rules[$idx].type // "free"' "$config" 2>/dev/null)

  local filter event
  case "$action" in
    disable) filter='.rules[$idx].enabled = false'; event="rule_disabled" ;;
    enable)  filter='.rules[$idx] |= del(.enabled)'; event="rule_enabled" ;;
    *) echo "_pm_rule_toggle: unknown action: $action" >&2; return 1 ;;
  esac

  local tmp
  tmp=$(mktemp "${config}.tmp.XXXXXX")
  if jq --argjson idx "$index" "$filter" "$config" > "$tmp"; then
    mv "$tmp" "$config"
  else
    rm -f "$tmp"; return 1
  fi

  write_rule_event "$event" "$index" "$type" "$user" "$reason"
}

policy_disable() {
  _pm_policy_toggle "$1" "disable" "${3:-${USER:-unknown}}" "${2:-No reason provided}"
}

policy_enable() {
  _pm_policy_toggle "$1" "enable" "${3:-${USER:-unknown}}" "${2:-No reason provided}"
}

policy_status() {
  local config="$LANEKEEP_CONFIG_FILE"
  [ -f "$config" ] || { echo "Config not found: $config" >&2; return 1; }

  jq -r '.policies // {} | to_entries[] | "\(.key)\t\(.value.type // "free")\t\(if .value.enabled == false then "disabled" else "enabled" end)"' "$config"
}

rule_disable() {
  _pm_rule_toggle "$1" "disable" "${3:-${USER:-unknown}}" "${2:-No reason provided}"
}

rule_enable() {
  _pm_rule_toggle "$1" "enable" "${3:-${USER:-unknown}}" "${2:-No reason provided}"
}
