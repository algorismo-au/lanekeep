#!/usr/bin/env bash
# Claude Code SessionStart hook — scan loaded memory files for injection markers.
#
# Runs when a Claude Code session starts, resumes, or is cleared. Reads the
# hook JSON from stdin (session_id, source, cwd, transcript_path,
# hook_event_name). For "resume" and "startup" sources, walks a small set of
# memory-relevant files that the model has (or will) ingest — CLAUDE.md,
# AGENTS.md, .claude/instructions/*.md — and passes each through the shipped
# hidden-text evaluator. Any match is warned to stderr and logged to the
# trace via write_policy_event.
#
# SessionStart hooks cannot gate the session — this script is defensive
# observability, not enforcement. Exit 0 always.

set -uo pipefail

# --- Resolve project root (walk up from cwd looking for lanekeep.json or .lanekeep/) ---
_ss_resolve_project_root() {
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
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null) || SOURCE="startup"

[ -n "$CWD" ] || CWD="$PWD"
PROJECT_ROOT="${PROJECT_DIR:-$(_ss_resolve_project_root "$CWD")}"
export PROJECT_DIR="$PROJECT_ROOT"

CONFIG_FILE="${LANEKEEP_CONFIG_FILE:-$PROJECT_ROOT/lanekeep.json}"
[ -f "$CONFIG_FILE" ] || [ ! -f "$PROJECT_ROOT/lanekeep.json.bak" ] || CONFIG_FILE="$PROJECT_ROOT/lanekeep.json.bak"
export LANEKEEP_CONFIG_FILE="$CONFIG_FILE"

# Session-start scan is opt-out via config: .hooks.session_start.scan_memory
if [ -f "$CONFIG_FILE" ]; then
  scan_enabled=$(jq -r 'if .hooks.session_start | has("scan_memory") then .hooks.session_start.scan_memory else true end' "$CONFIG_FILE" 2>/dev/null) || scan_enabled=true
  if [ "$scan_enabled" = "false" ]; then
    exit 0
  fi
fi

# Skip when source=clear — fresh session, no prior memory to worry about.
if [ "$SOURCE" = "clear" ]; then
  exit 0
fi

LANEKEEP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export LANEKEEP_SESSION_ID="${LANEKEEP_SESSION_ID:-$SESSION_ID}"
[ -n "${LANEKEEP_SESSION_ID}" ] || LANEKEEP_SESSION_ID="session-$(date -u +%Y%m%dT%H%M%SZ)"
export LANEKEEP_TRACE_FILE="${LANEKEEP_TRACE_FILE:-$PROJECT_ROOT/.lanekeep/traces/${LANEKEEP_SESSION_ID}.jsonl}"

# --- Enumerate memory files to scan ---
_ss_targets=()
for base in "CLAUDE.md" "AGENTS.md" "CURSOR.md" "COPILOT.md"; do
  [ -f "$PROJECT_ROOT/$base" ] && _ss_targets+=("$PROJECT_ROOT/$base")
done
if [ -d "$PROJECT_ROOT/.claude/instructions" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] && _ss_targets+=("$f")
  done < <(find "$PROJECT_ROOT/.claude/instructions" -maxdepth 3 -type f \( -name '*.md' -o -name '*.txt' \) 2>/dev/null)
fi

# Nothing to scan → done
if [ "${#_ss_targets[@]}" -eq 0 ]; then
  exit 0
fi

# --- Load hidden-text evaluator + trace writer ---
# shellcheck source=/dev/null
source "$LANEKEEP_DIR/lib/eval-hidden-text.sh"
# shellcheck source=/dev/null
source "$LANEKEEP_DIR/lib/trace.sh"

# Ensure trace directory exists
install -d -m 0700 "${LANEKEEP_TRACE_FILE%/*}" 2>/dev/null || true

# --- Scan each target with hidden_text_eval ---
# Cap file read at 128 KiB per target (same order as repo_injection MVP).
_SS_MAX_BYTES="${LANEKEEP_SESSION_START_MAX_BYTES:-131072}"
_ss_findings=0
for target in "${_ss_targets[@]}"; do
  content=$(head -c "$_SS_MAX_BYTES" "$target" 2>/dev/null) || continue
  [ -n "$content" ] || continue

  # Feed the file's content as tool_input; hidden_text_eval grep-scans the
  # blob directly and honours .evaluators.hidden_text.* config from disk.
  # Use "Write" as the synthetic tool_name because hidden_text_eval gates on
  # Write|Edit|Bash — semantically matches content-ingestion here.
  if ! hidden_text_eval "Write" "$content"; then
    rel="${target#"$PROJECT_ROOT"/}"
    _ss_findings=$((_ss_findings + 1))
    printf '[LaneKeep] SessionStart: %s pattern in %s (%s)\n' \
      "${HIDDEN_TEXT_DECISION:-warn}" "$rel" "${HIDDEN_TEXT_REASON:-hidden text}" >&2
    if declare -f write_policy_event >/dev/null 2>&1; then
      write_policy_event "session_start_scan" "lifecycle" "$SOURCE" "$USER" \
        "hidden-text pattern in $rel: ${HIDDEN_TEXT_DECISION:-warn}" 2>/dev/null || true
    fi
  fi
done

# Emit a session_start marker even on clean scan — makes lifecycle events
# visible in the trace timeline.
if [ "$_ss_findings" -eq 0 ] && declare -f write_policy_event >/dev/null 2>&1; then
  write_policy_event "session_start" "lifecycle" "$SOURCE" "$USER" \
    "scanned ${#_ss_targets[@]} memory file(s); no findings" 2>/dev/null || true
fi

exit 0
