#!/usr/bin/env bash
# Claude Code PreCompact hook — snapshot cross-session state before context
# compaction rewrites the transcript.
#
# Runs immediately before Claude Code compacts the active session's context.
# Reads the hook JSON from stdin (session_id, trigger, custom_instructions,
# transcript_path, cwd). Copies the LaneKeep cross-session signal files
# (cumulative.json + state.json) into .lanekeep/compaction-snapshots/ so
# subsequent audit queries can reconstruct the pre-compaction state.
#
# PreCompact hooks cannot cancel the compaction — this script is defensive
# observability, not enforcement. Exit 0 always.

set -uo pipefail

# --- Resolve project root (walk up from cwd looking for lanekeep.json or .lanekeep/) ---
_pc_resolve_project_root() {
  local dir="$1"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -f "$dir/lanekeep.json" ] || [ -d "$dir/.lanekeep" ]; then
      printf '%s' "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  printf '%s' "$1"
}

# --- Read stdin JSON ---
INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || CWD=""
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null) || SESSION_ID=""
TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // "auto"' 2>/dev/null) || TRIGGER="auto"

[ -n "$CWD" ] || CWD="$PWD"
PROJECT_ROOT="${PROJECT_DIR:-$(_pc_resolve_project_root "$CWD")}"
export PROJECT_DIR="$PROJECT_ROOT"

CONFIG_FILE="${LANEKEEP_CONFIG_FILE:-$PROJECT_ROOT/lanekeep.json}"
[ -f "$CONFIG_FILE" ] || [ ! -f "$PROJECT_ROOT/lanekeep.json.bak" ] || CONFIG_FILE="$PROJECT_ROOT/lanekeep.json.bak"
export LANEKEEP_CONFIG_FILE="$CONFIG_FILE"

# Opt-out: .hooks.pre_compact.snapshot = false → skip snapshotting.
if [ -f "$CONFIG_FILE" ]; then
  snap_enabled=$(jq -r 'if .hooks.pre_compact | has("snapshot") then .hooks.pre_compact.snapshot else true end' "$CONFIG_FILE" 2>/dev/null) || snap_enabled=true
  if [ "$snap_enabled" = "false" ]; then
    exit 0
  fi
fi

LANEKEEP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${LANEKEEP_STATE_DIR:-$PROJECT_ROOT/.lanekeep}"
SNAPSHOT_DIR="${LANEKEEP_COMPACTION_DIR:-$STATE_DIR/compaction-snapshots}"
export LANEKEEP_SESSION_ID="${LANEKEEP_SESSION_ID:-$SESSION_ID}"
[ -n "${LANEKEEP_SESSION_ID}" ] || LANEKEEP_SESSION_ID="session-$(date -u +%Y%m%dT%H%M%SZ)"
export LANEKEEP_TRACE_FILE="${LANEKEEP_TRACE_FILE:-$STATE_DIR/traces/${LANEKEEP_SESSION_ID}.jsonl}"

install -d -m 0700 "$SNAPSHOT_DIR" 2>/dev/null || true

# --- Compose the snapshot ---
# One JSON blob per compaction: metadata + copies of cumulative.json and
# state.json when present. Writing a single file (vs. multiple copies) makes
# downstream tooling / dashboard rendering simpler.
_pc_ts=$(date -u +%Y%m%dT%H%M%SZ)
_pc_epoch=$(date -u +%s)
_pc_file="$SNAPSHOT_DIR/${LANEKEEP_SESSION_ID}-${_pc_ts}.json"

# Load cumulative.json / state.json defensively — either may be missing.
_pc_cumulative="null"
_pc_state="null"
if [ -f "$STATE_DIR/cumulative.json" ]; then
  _pc_cumulative=$(jq -c '.' "$STATE_DIR/cumulative.json" 2>/dev/null) || _pc_cumulative="null"
fi
if [ -f "$STATE_DIR/state.json" ]; then
  _pc_state=$(jq -c '.' "$STATE_DIR/state.json" 2>/dev/null) || _pc_state="null"
fi

jq -n -c \
  --arg session_id "$LANEKEEP_SESSION_ID" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
  --argjson epoch "$_pc_epoch" \
  --arg trigger "$TRIGGER" \
  --arg cwd "$CWD" \
  --argjson cumulative "$_pc_cumulative" \
  --argjson state "$_pc_state" \
  '{
    schema: "lanekeep.compaction-snapshot/v1",
    session_id: $session_id,
    timestamp: $timestamp,
    epoch: $epoch,
    trigger: $trigger,
    cwd: $cwd,
    cumulative: $cumulative,
    state: $state
  }' > "$_pc_file" 2>/dev/null || true
chmod 600 "$_pc_file" 2>/dev/null || true

# --- Log the snapshot event to the trace ---
# shellcheck source=/dev/null
source "$LANEKEEP_DIR/lib/trace.sh"
if declare -f write_policy_event >/dev/null 2>&1; then
  install -d -m 0700 "${LANEKEEP_TRACE_FILE%/*}" 2>/dev/null || true
  _pc_rel="${_pc_file#"$PROJECT_ROOT"/}"
  write_policy_event "pre_compact_snapshot" "lifecycle" "$TRIGGER" "$USER" \
    "snapshot written to $_pc_rel" 2>/dev/null || true
fi

exit 0
