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
  # Fallback 4: LANEKEEP_CORRELATION_ID env var → registry lookup
  if [ -n "${LANEKEEP_CORRELATION_ID:-}" ]; then
    local _reg="${XDG_STATE_HOME:-$HOME/.local/state}/lanekeep/sockets/${LANEKEEP_CORRELATION_ID}.sock"
    if [ -L "$_reg" ] && [ -S "$(readlink -f "$_reg" 2>/dev/null)" ]; then
      printf '%s' "$(readlink -f "$_reg")"
      return
    fi
  fi
  # Fallback 5: Git worktree detection — find main project's socket via registry
  local _git_common
  _git_common=$(git rev-parse --git-common-dir 2>/dev/null) || true
  if [ -n "$_git_common" ] && [ "$_git_common" != ".git" ]; then
    local _main_project
    _main_project=$(cd "$_git_common/.." 2>/dev/null && pwd -P) || true
    if [ -n "$_main_project" ]; then
      local _main_corr
      _main_corr=$(printf '%s' "$_main_project" | sha256sum | cut -c1-16)
      local _reg="${XDG_STATE_HOME:-$HOME/.local/state}/lanekeep/sockets/${_main_corr}.sock"
      if [ -L "$_reg" ] && [ -S "$(readlink -f "$_reg" 2>/dev/null)" ]; then
        LANEKEEP_CORRELATION_ID="$_main_corr"
        printf '%s' "$(readlink -f "$_reg")"
        return
      fi
    fi
  fi
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
    local trace_file="$trace_dir/hook-fallback.jsonl"
    local entry
    entry=$(printf '%s' "$INPUT" | jq -c \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg dec "$decision" \
      --arg reason "$reason" \
      --arg corr_id "${LANEKEEP_CORRELATION_ID:-}" \
      '{timestamp:$ts, source:"lanekeep-hook", session_id:"hook-fallback",
        event_type:"PreToolUse", tool_name:(.tool_name // "unknown"),
        decision:$dec, reason:$reason, evaluators:[]}
      + (if (.tool_use_id // "") != "" then {tool_use_id} else {} end)
      + (if (.session_id // "") != "" then {cc_session_id: .session_id} else {} end)
      + (if (.agent_id // "") != "" then {agent_id} else {} end)
      + (if (.parent_session_id // "") != "" then {parent_session_id} else {} end)
      + (if (.agent_type // "") != "" then {agent_type} else {} end)
      + (if (.spawned_by // "") != "" then {spawned_by} else {} end)
      + (if has("agent_depth") then {agent_depth} else {} end)
      + (if (.isolation_type // "") != "" then {isolation_type} else {} end)
      + (if .is_background == true then {is_background: true} else {} end)
      + (if $corr_id != "" then {correlation_id: $corr_id} else {} end)') || return 0
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
