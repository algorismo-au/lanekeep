#!/bin/bash
# Claude Code PreToolUse hook -> LaneKeep sidecar bridge
# Forwards tool call JSON to LaneKeep over Unix domain socket, returns hookSpecificOutput.
# VULN-09: Fail-closed by default (LANEKEEP_FAIL_POLICY=allow to override).

TIMEOUT="${LANEKEEP_HOOK_TIMEOUT:-4}"
FAIL_POLICY="${LANEKEEP_FAIL_POLICY:-deny}"

# Resolve socket: explicit env > PROJECT_DIR > walk up from PWD to find .lanekeep/
_resolve_socket() {
  if [ -n "${LANEKEEP_SOCKET:-}" ]; then
    printf '%s' "$LANEKEEP_SOCKET"
    return
  fi
  local base="${PROJECT_DIR:-}"
  if [ -n "$base" ] && [ -S "$base/.lanekeep/lanekeep.sock" ]; then
    printf '%s' "$base/.lanekeep/lanekeep.sock"
    return
  fi
  # Walk up from PWD — handles worktrees / subagents with different PWD
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -S "$dir/.lanekeep/lanekeep.sock" ]; then
      printf '%s' "$dir/.lanekeep/lanekeep.sock"
      return
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback: expected path (will trigger fail-policy downstream)
  printf '%s' "${PROJECT_DIR:-$PWD}/.lanekeep/lanekeep.sock"
}
SOCKET="$(_resolve_socket)"

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
if ! RESPONSE=$(printf '%s' "$INPUT" | socat -t "$TIMEOUT" - UNIX-CONNECT:"$SOCKET" 2>/dev/null) || [ -z "$RESPONSE" ]; then
  # Stale socket — sidecar died without cleanup. Remove and try one restart.
  if [ -S "$SOCKET" ] && ! lsof -t "$SOCKET" >/dev/null 2>&1; then
    rm -f "$SOCKET" "$(dirname "$SOCKET")/lanekeep-serve.pid" "$(dirname "$SOCKET")/lanekeep-serve.lock"
    # Attempt background restart if lanekeep-serve is on PATH
    if command -v lanekeep-serve >/dev/null 2>&1; then
      PROJECT_DIR="${PROJECT_DIR:-$PWD}" lanekeep-serve </dev/null >/dev/null 2>&1 &
      # Wait briefly for socket to appear
      for _w in 1 2 3 4 5 6 7 8 9 10; do
        [ -S "$SOCKET" ] && break
        sleep 0.1
      done
      # Retry the request once
      if [ -S "$SOCKET" ]; then
        if RESPONSE=$(printf '%s' "$INPUT" | socat -t "$TIMEOUT" - UNIX-CONNECT:"$SOCKET" 2>/dev/null) && [ -n "$RESPONSE" ]; then
          # Recovery succeeded — fall through to decision parsing
          :
        else
          _lanekeep_fail_policy "Sidecar restart attempted but still unreachable."
        fi
      else
        _lanekeep_fail_policy "Sidecar restart attempted but socket not ready."
      fi
    else
      _lanekeep_fail_policy "Stale socket detected. Run: lanekeep serve"
    fi
  else
    _lanekeep_fail_policy "Failed to reach LaneKeep sidecar."
  fi
fi

# Extract decision
DECISION=$(printf '%s' "$RESPONSE" | jq -r '.decision // "deny"')
WARN=$(printf '%s' "$RESPONSE" | jq -r '.warn // empty')

case "$DECISION" in
  deny)
    REASON=$(printf '%s' "$RESPONSE" | jq -r '.reason // "[LaneKeep] DENIED: Unknown reason"')
    jq -n -c --arg reason "$REASON" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }' 2>/dev/null
    ;;
  ask)
    REASON=$(printf '%s' "$RESPONSE" | jq -r '.reason // "[LaneKeep] NEEDS APPROVAL"')
    jq -n -c --arg reason "$REASON" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
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
