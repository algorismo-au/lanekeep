#!/bin/bash
# Cursor PreToolUse hook -> LaneKeep sidecar bridge
# Cursor uses near-identical hook format to Claude Code.
# Key difference: exit code 2 = deny (vs Claude Code's JSON response).

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

if ! RESPONSE=$(printf '%s' "$INPUT" | socat -t "$TIMEOUT" - UNIX-CONNECT:"$SOCKET" 2>/dev/null) || [ -z "$RESPONSE" ]; then
  _lanekeep_fail_policy "Failed to reach LaneKeep sidecar."
fi

DECISION=$(printf '%s' "$RESPONSE" | jq -r '.decision // "deny"')
REASON=$(printf '%s' "$RESPONSE" | jq -r '.reason // empty')

case "$DECISION" in
  deny)
    echo "[LaneKeep] DENIED: ${REASON:-Unknown reason}" >&2
    exit 2
    ;;
  ask)
    echo "[LaneKeep] NEEDS APPROVAL: ${REASON:-Requires user approval}" >&2
    exit 2
    ;;
  allow)
    WARN=$(printf '%s' "$RESPONSE" | jq -r '.warn // empty')
    if [ -n "$WARN" ]; then
      echo "[LaneKeep] WARNING: $WARN" >&2
    fi
    exit 0
    ;;
  *)
    # Unrecognized decision — fail-closed
    echo "[LaneKeep] DENIED: unrecognized decision '$DECISION'" >&2
    exit 2
    ;;
esac

# shellcheck disable=SC2317  # defensive fail-closed — unreachable unless case branches change
exit 2
