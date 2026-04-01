#!/usr/bin/env bash
# webhook — forwards evaluations to an HTTP endpoint
# Copy to plugins.d/ to activate. Requires LANEKEEP_WEBHOOK_URL.
#
# Config:
#   LANEKEEP_WEBHOOK_URL       Required. POST endpoint for tool call evaluations.
#   LANEKEEP_WEBHOOK_TIMEOUT   Optional. Curl timeout in seconds (default: 2).
#
# Protocol:
#   POST {"tool_name":"...","tool_input":{...}}
#   Response: {"passed":true/false,"reason":"...","decision":"deny|ask|warn"}
#
# Fail-open: on timeout, curl error, non-2xx, or JSON parse failure → pass.

WEBHOOK_PASSED=true
WEBHOOK_REASON=""
WEBHOOK_DECISION="deny"

webhook_eval() {
  local tool_name="$1"
  local tool_input="$2"
  WEBHOOK_PASSED=true
  WEBHOOK_REASON=""
  WEBHOOK_DECISION="deny"

  local url="${LANEKEEP_WEBHOOK_URL:-}"
  if [ -z "$url" ]; then
    # No URL configured — no-op pass
    return 0
  fi

  # Validate URL: HTTPS only, no loopback/internal addresses
  case "$url" in
    https://*) ;;
    *)
      echo "webhook: LANEKEEP_WEBHOOK_URL must use https://" >&2
      return 0
      ;;
  esac
  local host
  host=$(printf '%s' "$url" | sed -n 's|^https://\([^:/]*\).*|\1|p')
  case "$host" in
    localhost|127.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|192.168.*|169.254.*|0.0.0.0|"")
      echo "webhook: LANEKEEP_WEBHOOK_URL must not point to internal/loopback addresses" >&2
      return 0
      ;;
  esac

  local timeout="${LANEKEEP_WEBHOOK_TIMEOUT:-2}"
  local payload
  payload=$(jq -n --arg name "$tool_name" --argjson input "$tool_input" \
    '{tool_name: $name, tool_input: $input}') || {
    echo "webhook: JSON construction failed" >&2
    return 0
  }

  local response http_code
  response=$(curl -s -S --max-time "$timeout" --connect-timeout "$timeout" \
    -w '\n%{http_code}' \
    -H 'Content-Type: application/json' \
    -d "$payload" "$url" 2>/dev/null) || {
    echo "webhook: curl failed for $url" >&2
    return 0  # fail-open
  }

  # Split response body and HTTP status code
  http_code=$(printf '%s' "$response" | tail -1)
  response=$(printf '%s' "$response" | sed '$d')

  # Non-2xx → fail-open
  case "$http_code" in
    2[0-9][0-9]) ;;
    *)
      echo "webhook: non-2xx response ($http_code) from $url" >&2
      return 0
      ;;
  esac

  # Parse JSON response
  local passed reason decision
  passed=$(printf '%s' "$response" | jq -r 'if .passed == false then "false" else "true" end' 2>/dev/null) || {
    echo "webhook: JSON parse failed" >&2
    return 0  # fail-open
  }
  reason=$(printf '%s' "$response" | jq -r '.reason // ""' 2>/dev/null) || reason=""
  decision=$(printf '%s' "$response" | jq -r '.decision // "deny"' 2>/dev/null) || decision="deny"

  WEBHOOK_PASSED="$passed"
  WEBHOOK_REASON="$reason"
  WEBHOOK_DECISION="$decision"

  if [ "$passed" = "false" ]; then
    return 1
  fi
  return 0
}

LANEKEEP_PLUGIN_EVALS="${LANEKEEP_PLUGIN_EVALS:-} webhook_eval"
