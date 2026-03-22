#!/usr/bin/env bash
# Ralph context: tracks current iteration, hat, and topic from Ralph events.
# Two modes:
#   watch <dir>  — background: tails events-*.jsonl, writes state file
#   context      — reads state file, outputs JSON for trace enrichment

set -euo pipefail

RALPH_STATE_FILE="${LANEKEEP_STATE_DIR:-.lanekeep}/ralph-state.json"

_ralph_init_state() {
  mkdir -p "$(dirname "$RALPH_STATE_FILE")"
  printf '{"iteration":0,"hat":"unknown","topic":"unknown"}\n' > "$RALPH_STATE_FILE"
}

_ralph_update_from_line() {
  local line="$1"

  # Validate JSON first
  printf '%s' "$line" | jq -e '.' >/dev/null 2>&1 || return 0

  # Extract fields with defaults for events that omit them
  local iteration hat topic
  iteration=$(printf '%s' "$line" | jq -r '.iteration // empty' 2>/dev/null)
  hat=$(printf '%s' "$line" | jq -r '.hat // empty' 2>/dev/null)
  topic=$(printf '%s' "$line" | jq -r '.topic // empty' 2>/dev/null)

  # Only update fields that are present in this event
  local updates=""
  [ -n "$iteration" ] && updates="${updates} --argjson i $iteration"
  [ -n "$hat" ] && updates="${updates} --arg h $hat"
  [ -n "$topic" ] && updates="${updates} --arg t $topic"

  [ -z "$updates" ] && return 0

  # Build jq filter based on which fields are present
  local filter=""
  [ -n "$iteration" ] && filter="${filter} | .iteration = \$i"
  [ -n "$hat" ] && filter="${filter} | .hat = \$h"
  [ -n "$topic" ] && filter="${filter} | .topic = \$t"
  filter="${filter# | }"  # remove leading " | "

  jq -c $updates "$filter" "$RALPH_STATE_FILE" > "${RALPH_STATE_FILE}.tmp" \
    && mv "${RALPH_STATE_FILE}.tmp" "$RALPH_STATE_FILE"
}

ralph_watch() {
  local events_dir="$1"

  if [ ! -d "$events_dir" ]; then
    return 0
  fi

  _ralph_init_state

  # Process existing events first
  local f
  for f in "$events_dir"/events-*.jsonl; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      _ralph_update_from_line "$line"
    done < "$f"
  done

  # Then tail for new events (blocks — run in background)
  # Use inotifywait if available, otherwise poll
  if command -v inotifywait >/dev/null 2>&1; then
    while true; do
      inotifywait -q -e modify -e create "$events_dir" >/dev/null 2>&1 || true
      for f in "$events_dir"/events-*.jsonl; do
        [ -f "$f" ] || continue
        # Re-read last line (simple approach — events are append-only)
        local last
        last=$(tail -1 "$f" 2>/dev/null)
        [ -n "$last" ] && _ralph_update_from_line "$last"
      done
    done
  else
    # Fallback: poll every 2 seconds
    while true; do
      sleep 2
      for f in "$events_dir"/events-*.jsonl; do
        [ -f "$f" ] || continue
        local last
        last=$(tail -1 "$f" 2>/dev/null)
        [ -n "$last" ] && _ralph_update_from_line "$last"
      done
    done
  fi
}

ralph_context() {
  if [ -f "$RALPH_STATE_FILE" ]; then
    jq -c '.' "$RALPH_STATE_FILE" 2>/dev/null || echo '{"iteration":0,"hat":"unknown","topic":"unknown"}'
  else
    echo '{"iteration":0,"hat":"unknown","topic":"unknown"}'
  fi
}

# --- CLI dispatch (skip when sourced) ---
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    watch)
      ralph_watch "${2:?Usage: ralph-context.sh watch <events-dir>}"
      ;;
    context)
      ralph_context
      ;;
    *)
      echo "Usage: ralph-context.sh {watch <dir>|context}" >&2
      exit 1
      ;;
  esac
fi
