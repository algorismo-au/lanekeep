#!/bin/bash
# Cursor PostToolUse hook -> LaneKeep sidecar bridge
# Sends tool result through LaneKeep's Tier 5 (ResultTransform) for output scanning.

SOCKET="${LANEKEEP_SOCKET:-$PWD/.lanekeep/lanekeep.sock}"
TIMEOUT="${LANEKEEP_HOOK_TIMEOUT:-2}"
FAIL_POLICY="${LANEKEEP_FAIL_POLICY:-deny}"

# Warn if socket path exceeds Unix limit (108 bytes)
if [ ${#SOCKET} -gt 108 ]; then
  echo "[LaneKeep] WARNING: Socket path too long (${#SOCKET} > 108 bytes): $SOCKET" >&2
  echo "[LaneKeep] Fix: set LANEKEEP_SOCKET to a shorter path, e.g. /tmp/lanekeep-\$PROJECT.sock" >&2
fi

_lanekeep_fail_policy() {
  local context="$1"
  if [ "$FAIL_POLICY" = "allow" ]; then
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓" >&2
    echo "┃  WARNING: LANEKEEP GOVERNANCE BYPASSED (FAIL_POLICY=allow) ┃" >&2
    echo "┃  $context" >&2
    echo "┃  Unset LANEKEEP_FAIL_POLICY to restore protection.        ┃" >&2
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛" >&2
    exit 0
  fi
  echo "[LaneKeep] DENIED: $context Sidecar unreachable and LANEKEEP_FAIL_POLICY=deny." >&2
  exit 2
}

INPUT=$(cat)

if [ ! -S "$SOCKET" ]; then
  _lanekeep_fail_policy "LaneKeep sidecar not running."
fi

# Inject hook_event_name so lanekeep-handler routes to PostToolUse pipeline
ENRICHED=$(printf '%s' "$INPUT" | jq -c '. + {"hook_event_name": "PostToolUse"}' 2>/dev/null) || ENRICHED="$INPUT"

RESPONSE=$(printf '%s' "$ENRICHED" | socat -t "$TIMEOUT" - UNIX-CONNECT:"$SOCKET" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
  _lanekeep_fail_policy "Failed to reach LaneKeep sidecar."
fi

DECISION=$(printf '%s' "$RESPONSE" | jq -r '.decision // "allow"')

case "$DECISION" in
  deny)
    REASON=$(printf '%s' "$RESPONSE" | jq -r '.reason // "Blocked by LaneKeep"')
    echo "[LaneKeep] DENIED (post): $REASON" >&2
    exit 2
    ;;
  allow)
    WARN=$(printf '%s' "$RESPONSE" | jq -r '.warn // empty')
    if [ -n "$WARN" ]; then
      echo "[LaneKeep] WARNING (post): $WARN" >&2
    fi
    exit 0
    ;;
esac

exit 0
