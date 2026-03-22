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

  local timeout="${LANEKEEP_WEBHOOK_TIMEOUT:-2}"
  local payload
  payload=$(printf '{"tool_name":"%s","tool_input":%s}' \
    "$(printf '%s' "$tool_name" | sed 's/"/\\"/g')" "$tool_input")

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
