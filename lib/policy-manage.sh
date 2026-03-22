#!/usr/bin/env bash
# Policy and rule management: disable/enable with audit trail

policy_disable() {
  local category="$1"
  local reason="${2:-No reason provided}"
  local user="${3:-${USER:-unknown}}"
  local config="$LANEKEEP_CONFIG_FILE"

  [ -f "$config" ] || { echo "Config not found: $config" >&2; return 1; }

  # Verify category exists
  local exists
  exists=$(jq --arg cat "$category" 'has("policies") and (.policies | has($cat))' "$config" 2>/dev/null)
  [ "$exists" = "true" ] || { echo "Policy category not found: $category" >&2; return 1; }

  # Read type for audit trail
  local type
  type=$(jq -r --arg cat "$category" '.policies[$cat].type // "free"' "$config" 2>/dev/null)

  # Set enabled=false
  local tmp
  tmp=$(mktemp "${config}.tmp.XXXXXX")
  jq --arg cat "$category" '.policies[$cat].enabled = false' "$config" > "$tmp" && mv "$tmp" "$config" || { rm -f "$tmp"; return 1; }

  # Write audit trail
  write_policy_event "policy_disabled" "$category" "$type" "$user" "$reason"
}

policy_enable() {
  local category="$1"
  local reason="${2:-No reason provided}"
  local user="${3:-${USER:-unknown}}"
  local config="$LANEKEEP_CONFIG_FILE"

  [ -f "$config" ] || { echo "Config not found: $config" >&2; return 1; }

  # Verify category exists
  local exists
  exists=$(jq --arg cat "$category" 'has("policies") and (.policies | has($cat))' "$config" 2>/dev/null)
  [ "$exists" = "true" ] || { echo "Policy category not found: $category" >&2; return 1; }

  # Read type for audit trail
  local type
  type=$(jq -r --arg cat "$category" '.policies[$cat].type // "free"' "$config" 2>/dev/null)

  # Remove enabled field (defaults to true)
  local tmp
  tmp=$(mktemp "${config}.tmp.XXXXXX")
  jq --arg cat "$category" '.policies[$cat] |= del(.enabled)' "$config" > "$tmp" && mv "$tmp" "$config" || { rm -f "$tmp"; return 1; }

  # Write audit trail
  write_policy_event "policy_enabled" "$category" "$type" "$user" "$reason"
}

policy_status() {
  local config="$LANEKEEP_CONFIG_FILE"
  [ -f "$config" ] || { echo "Config not found: $config" >&2; return 1; }

  jq -r '.policies // {} | to_entries[] | "\(.key)\t\(.value.type // "free")\t\(if .value.enabled == false then "disabled" else "enabled" end)"' "$config"
}

rule_disable() {
  local index="$1"
  local reason="${2:-No reason provided}"
  local user="${3:-${USER:-unknown}}"
  local config="$LANEKEEP_CONFIG_FILE"

  [ -f "$config" ] || { echo "Config not found: $config" >&2; return 1; }

  # Verify index is valid
  local count
  count=$(jq '.rules | length' "$config" 2>/dev/null)
  [ "$index" -ge 0 ] && [ "$index" -lt "$count" ] 2>/dev/null || { echo "Rule index out of range: $index (have $count rules)" >&2; return 1; }

  # Read type for audit trail
  local type
  type=$(jq -r --argjson idx "$index" '.rules[$idx].type // "free"' "$config" 2>/dev/null)

  # Set enabled=false
  local tmp
  tmp=$(mktemp "${config}.tmp.XXXXXX")
  jq --argjson idx "$index" '.rules[$idx].enabled = false' "$config" > "$tmp" && mv "$tmp" "$config" || { rm -f "$tmp"; return 1; }

  # Write audit trail
  write_rule_event "rule_disabled" "$index" "$type" "$user" "$reason"
}

rule_enable() {
  local index="$1"
  local reason="${2:-No reason provided}"
  local user="${3:-${USER:-unknown}}"
  local config="$LANEKEEP_CONFIG_FILE"

  [ -f "$config" ] || { echo "Config not found: $config" >&2; return 1; }

  # Verify index is valid
  local count
  count=$(jq '.rules | length' "$config" 2>/dev/null)
  [ "$index" -ge 0 ] && [ "$index" -lt "$count" ] 2>/dev/null || { echo "Rule index out of range: $index (have $count rules)" >&2; return 1; }

  # Read type for audit trail
  local type
  type=$(jq -r --argjson idx "$index" '.rules[$idx].type // "free"' "$config" 2>/dev/null)

  # Remove enabled field (defaults to true)
  local tmp
  tmp=$(mktemp "${config}.tmp.XXXXXX")
  jq --argjson idx "$index" '.rules[$idx] |= del(.enabled)' "$config" > "$tmp" && mv "$tmp" "$config" || { rm -f "$tmp"; return 1; }

  # Write audit trail
  write_rule_event "rule_enabled" "$index" "$type" "$user" "$reason"
}
