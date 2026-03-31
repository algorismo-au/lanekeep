#!/bin/bash
# Claude Code PreToolUse hook -> LaneKeep sidecar bridge
# Forwards tool call JSON to LaneKeep over Unix domain socket, returns hookSpecificOutput.
# VULN-09: Fail-closed by default (LANEKEEP_FAIL_POLICY=allow to override).

SOCKET="${LANEKEEP_SOCKET:-${PROJECT_DIR:-$PWD}/.lanekeep/lanekeep.sock}"
TIMEOUT="${LANEKEEP_HOOK_TIMEOUT:-4}"
FAIL_POLICY="${LANEKEEP_FAIL_POLICY:-deny}"

# Warn if socket path exceeds Unix limit (108 bytes)
if [ ${#SOCKET} -gt 108 ]; then
  echo "[LaneKeep] WARNING: Socket path too long (${#SOCKET} > 108 bytes): $SOCKET" >&2
  echo "[LaneKeep] Fix: set LANEKEEP_SOCKET to a shorter path, e.g. /tmp/lanekeep-\$PROJECT.sock" >&2
fi

# Helper: write fallback trace when sidecar is unreachable
_write_fallback_trace() {
  local decision="$1" reason="$2"
  (
    local trace_dir="$PWD/.lanekeep/traces"
    (umask 077; mkdir -p "$trace_dir")
    local fields
    fields=$(printf '%s' "$INPUT" | jq -r '[.tool_name // "unknown", .tool_use_id // "unknown", .session_id // "unknown"] | @tsv' 2>/dev/null) || return 0
    local tool_name tool_use_id session_id
    tool_name=$(printf '%s' "$fields" | cut -f1)
    tool_use_id=$(printf '%s' "$fields" | cut -f2)
    session_id=$(printf '%s' "$fields" | cut -f3)
    local trace_file="$trace_dir/hook-fallback.jsonl"
    local entry
    entry=$(jq -n -c \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg sid "$session_id" \
      --arg tn "$tool_name" \
      --arg dec "$decision" \
      --arg reason "$reason" \
      --arg tuid "$tool_use_id" \
      '{timestamp:$ts,source:"lanekeep-hook",session_id:$sid,event_type:"PreToolUse",tool_name:$tn,decision:$dec,reason:$reason,evaluators:[],tool_use_id:$tuid}') || return 0
    (flock -n 9 && printf '%s\n' "$entry" >> "$trace_file" && chmod 0600 "$trace_file") 9>>"${trace_file}.lock" || true
  ) || return 0
}

# Helper: apply fail policy when sidecar is unreachable
_lanekeep_fail_policy() {
  local context="$1"
  local decision reason
  if [ "$FAIL_POLICY" = "allow" ]; then
    decision="allow"
    reason="[LaneKeep] WARNING: $context Tool call allowed without governance."
    _write_fallback_trace "$decision" "$reason"
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓" >&2
    echo "┃  WARNING: LANEKEEP GOVERNANCE BYPASSED (FAIL_POLICY=allow) ┃" >&2
    echo "┃  $context" >&2
    echo "┃  Unset LANEKEEP_FAIL_POLICY to restore protection.        ┃" >&2
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛" >&2
    exit 0
  fi
  # Fail-closed: deny the tool call
  decision="deny"
  reason="[LaneKeep] DENIED: $context Sidecar unreachable and LANEKEEP_FAIL_POLICY=deny."
  _write_fallback_trace "$decision" "$reason"
  jq -n -c --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }' 2>/dev/null
  exit 0
}

# Read hook input from stdin first (avoids stdin inheritance issues)
INPUT=$(cat)

# LaneKeep not running
if [ ! -S "$SOCKET" ]; then
  _lanekeep_fail_policy "LaneKeep sidecar not running."
fi

# Forward to LaneKeep via socat (already a LaneKeep dependency, unlike nc which varies by distro)
# Connection failed
if ! RESPONSE=$(printf '%s' "$INPUT" | socat -t "$TIMEOUT" - UNIX-CONNECT:"$SOCKET" 2>/dev/null) || [ -z "$RESPONSE" ]; then
  _lanekeep_fail_policy "Failed to reach LaneKeep sidecar."
fi

# Extract decision
DECISION=$(printf '%s' "$RESPONSE" | jq -r '.decision // "deny"')
WARN=$(printf '%s' "$RESPONSE" | jq -r '.warn // empty')

case "$DECISION" in
  deny|ask)
    REASON=$(printf '%s' "$RESPONSE" | jq -r '.reason // "[LaneKeep] DENIED: Unknown reason"')
    # Claude Code only recognizes "allow" and "deny" — map "ask" to "deny"
    # so the tool is blocked and the reason (with NEEDS APPROVAL tag) is shown
    jq -n -c --arg reason "$REASON" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }' 2>/dev/null
    ;;
  warn)
    jq -n -c --arg ctx "$WARN" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: $ctx
      }
    }' 2>/dev/null
    ;;
  allow)
    if [ -n "$WARN" ]; then
      jq -n -c --arg ctx "$WARN" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "allow",
          additionalContext: $ctx
        }
      }' 2>/dev/null
    fi
    ;;
  *)
    # Unrecognized decision — fail-closed
    jq -n -c --arg reason "[LaneKeep] DENIED: unrecognized decision '$DECISION'" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }' 2>/dev/null
    ;;
esac

exit 0
