#!/usr/bin/env bash
# Claude Code Stop hook — desktop notification with session summary
# Standalone hook (not sidecar-based). Reads state directly from .lanekeep/state.json.
# Exit 0 always — notifications never block the agent.

set -uo pipefail

STATE_FILE="${LANEKEEP_STATE_FILE:-$PWD/.lanekeep/state.json}"
TRACE_DIR="${LANEKEEP_TRACE_DIR:-$PWD/.lanekeep/traces}"
CONFIG_FILE="${LANEKEEP_CONFIG_FILE:-$PWD/lanekeep.json}"
[ -f "$CONFIG_FILE" ] || [ ! -f "$PWD/lanekeep.json.bak" ] || CONFIG_FILE="$PWD/lanekeep.json.bak"

# Read stdin (required by hook protocol, but we don't use it)
cat >/dev/null

# Check if notifications are enabled (jq // treats false as null, use if/then)
if [ -f "$CONFIG_FILE" ]; then
  enabled=$(jq -r 'if .notifications | has("enabled") then .notifications.enabled else true end' "$CONFIG_FILE" 2>/dev/null)
  on_stop=$(jq -r 'if .notifications | has("on_stop") then .notifications.on_stop else true end' "$CONFIG_FILE" 2>/dev/null)
  min_seconds=$(jq -r '.notifications.min_session_seconds // 30' "$CONFIG_FILE" 2>/dev/null)
  if [ "$enabled" = "false" ] || [ "$on_stop" = "false" ]; then
    exit 0
  fi

  # Platform-specific notification check
  current_platform=""
  case "$(uname)" in
    Darwin) current_platform="macos" ;;
    Linux)  current_platform="linux" ;;
    MINGW*|MSYS*|CYGWIN*) current_platform="windows" ;;
  esac

  if [ -n "$current_platform" ]; then
    # Support both new .platform (string) and legacy .platforms (object) formats
    configured_platform=$(jq -r '.notifications.platform // empty' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$configured_platform" ]; then
      if [ "$configured_platform" != "$current_platform" ]; then
        exit 0
      fi
    else
      # Legacy: check old .platforms object format
      platform_enabled=$(jq -r "if .notifications.platforms | has(\"$current_platform\") then .notifications.platforms.\"$current_platform\" else true end" "$CONFIG_FILE" 2>/dev/null)
      if [ "$platform_enabled" = "false" ]; then
        exit 0
      fi
    fi
  fi
else
  min_seconds=30
fi

# Extract session stats from state file
action_count=0
start_epoch=0
if [ -f "$STATE_FILE" ]; then
  action_count=$(jq -r '.action_count // 0' "$STATE_FILE" 2>/dev/null) || action_count=0
  start_epoch=$(jq -r '.start_epoch // 0' "$STATE_FILE" 2>/dev/null) || start_epoch=0
fi

# Calculate elapsed time
now_epoch=$(date +%s)
if [ "$start_epoch" -gt 0 ] 2>/dev/null; then
  elapsed=$((now_epoch - start_epoch))
else
  elapsed=0
fi

# Suppress for short sessions
if [ "$elapsed" -lt "${min_seconds:-30}" ] 2>/dev/null; then
  exit 0
fi

# Count denies from latest trace file
deny_count=0
if [ -d "$TRACE_DIR" ]; then
  latest_trace=$(find "$TRACE_DIR" -maxdepth 1 -name "*.jsonl" -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2- | head -1)
  if [ -n "$latest_trace" ]; then
    deny_count=$(grep -c '"deny"' "$latest_trace" 2>/dev/null) || deny_count=0
  fi
fi

# Format elapsed time
if [ "$elapsed" -ge 3600 ]; then
  elapsed_str="$((elapsed / 3600))h$((elapsed % 3600 / 60))m"
elif [ "$elapsed" -ge 60 ]; then
  elapsed_str="$((elapsed / 60))m$((elapsed % 60))s"
else
  elapsed_str="${elapsed}s"
fi

SUMMARY="Session done: ${action_count} actions, ${deny_count} denied, ${elapsed_str} elapsed"

# Platform detection: send notification
if [ "$(uname)" = "Darwin" ]; then
  osascript -e "display notification \"$SUMMARY\" with title \"LaneKeep\"" 2>/dev/null || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "LaneKeep" "$SUMMARY" 2>/dev/null || true
else
  # Fallback: terminal bell + stderr
  printf '\a' 2>/dev/null || true
  echo "[LaneKeep] $SUMMARY" >&2
fi

exit 0
