#!/usr/bin/env bats
# Tests for trace clear (prune_traces + lanekeep trace clear CLI)

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  TRACE_DIR="$TEST_TMP/.lanekeep/traces"
  mkdir -p "$TRACE_DIR"

  export LANEKEEP_SESSION_ID="current-session"
  export LANEKEEP_TRACE_FILE="$TRACE_DIR/current-session.jsonl"
  export PROJECT_DIR="$TEST_TMP"

  source "$LANEKEEP_DIR/lib/trace.sh"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

# --- prune_traces: clear keeps current session ---
@test "prune_traces keeps current session, deletes others" {
  echo '{}' > "$TRACE_DIR/current-session.jsonl"
  echo '{}' > "$TRACE_DIR/old-session-1.jsonl"
  echo '{}' > "$TRACE_DIR/old-session-2.jsonl"

  prune_traces "$TRACE_DIR" 0 0 true "current-session"

  [ -f "$TRACE_DIR/current-session.jsonl" ]
  [ ! -f "$TRACE_DIR/old-session-1.jsonl" ]
  [ ! -f "$TRACE_DIR/old-session-2.jsonl" ]
  [ "$PRUNE_DELETED" -eq 2 ]
}

# --- prune_traces: --all deletes everything ---
@test "prune_traces with keep_current=false deletes all" {
  echo '{}' > "$TRACE_DIR/current-session.jsonl"
  echo '{}' > "$TRACE_DIR/old-session-1.jsonl"

  prune_traces "$TRACE_DIR" 0 0 false ""

  [ ! -f "$TRACE_DIR/current-session.jsonl" ]
  [ ! -f "$TRACE_DIR/old-session-1.jsonl" ]
  [ "$PRUNE_DELETED" -eq 2 ]
}

# --- prune_traces: older-than filters by age ---
@test "prune_traces deletes files older than retention_days" {
  echo '{}' > "$TRACE_DIR/old-file.jsonl"
  touch -d "60 days ago" "$TRACE_DIR/old-file.jsonl"
  echo '{}' > "$TRACE_DIR/recent-file.jsonl"

  prune_traces "$TRACE_DIR" 30 0 false ""

  [ ! -f "$TRACE_DIR/old-file.jsonl" ]
  [ -f "$TRACE_DIR/recent-file.jsonl" ]
  [ "$PRUNE_DELETED" -eq 1 ]
}

# --- prune_traces: no files is a no-op ---
@test "prune_traces with no files is a no-op" {
  prune_traces "$TRACE_DIR" 0 0 false ""
  [ "$PRUNE_DELETED" -eq 0 ]
}

# --- prune_traces: rejects paths outside .lanekeep/traces ---
@test "prune_traces rejects path outside .lanekeep/traces" {
  run prune_traces "/tmp/not-a-lanekeep-dir" 0 0 false ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a .lanekeep/traces directory"* ]]
}

# --- prune_traces: removes .lock files alongside .jsonl ---
@test "prune_traces removes lock files alongside jsonl" {
  echo '{}' > "$TRACE_DIR/old-session.jsonl"
  echo '' > "$TRACE_DIR/old-session.jsonl.lock"

  prune_traces "$TRACE_DIR" 0 0 false ""

  [ ! -f "$TRACE_DIR/old-session.jsonl" ]
  [ ! -f "$TRACE_DIR/old-session.jsonl.lock" ]
}

# --- prune_traces: max_sessions cap ---
@test "prune_traces respects max_sessions cap" {
  # Create 5 files with staggered mtimes
  for i in 1 2 3 4 5; do
    echo "{}" > "$TRACE_DIR/session-$i.jsonl"
    touch -d "$((6 - i)) days ago" "$TRACE_DIR/session-$i.jsonl"
  done

  # Keep only 3 newest
  prune_traces "$TRACE_DIR" 0 3 false ""

  [ "$PRUNE_DELETED" -eq 2 ]
  # Newest 3 should remain (session-3, session-4, session-5 have most recent mtimes)
  [ -f "$TRACE_DIR/session-3.jsonl" ] || [ -f "$TRACE_DIR/session-4.jsonl" ] || [ -f "$TRACE_DIR/session-5.jsonl" ]
}

# --- CLI: lanekeep trace clear ---
@test "lanekeep trace clear deletes non-current sessions" {
  echo '{}' > "$TRACE_DIR/current-session.jsonl"
  echo '{}' > "$TRACE_DIR/other-session.jsonl"

  output=$("$LANEKEEP_DIR/bin/lanekeep-trace" clear)

  [ -f "$TRACE_DIR/current-session.jsonl" ]
  [ ! -f "$TRACE_DIR/other-session.jsonl" ]
  [[ "$output" == *"Cleared 1 file"* ]]
}

# --- CLI: lanekeep trace clear --all ---
@test "lanekeep trace clear --all deletes everything" {
  echo '{}' > "$TRACE_DIR/current-session.jsonl"
  echo '{}' > "$TRACE_DIR/other-session.jsonl"

  output=$("$LANEKEEP_DIR/bin/lanekeep-trace" clear --all)

  [ ! -f "$TRACE_DIR/current-session.jsonl" ]
  [ ! -f "$TRACE_DIR/other-session.jsonl" ]
  [[ "$output" == *"Cleared 2 file"* ]]
}

# --- CLI: lanekeep trace clear --older-than ---
@test "lanekeep trace clear --older-than 30d filters by age" {
  echo '{}' > "$TRACE_DIR/old-file.jsonl"
  touch -d "60 days ago" "$TRACE_DIR/old-file.jsonl"
  echo '{}' > "$TRACE_DIR/recent-file.jsonl"

  output=$("$LANEKEEP_DIR/bin/lanekeep-trace" clear --older-than 30d)

  [ ! -f "$TRACE_DIR/old-file.jsonl" ]
  [ -f "$TRACE_DIR/recent-file.jsonl" ]
  [[ "$output" == *"Cleared 1 file"* ]]
}

# --- CLI: no files to clear ---
@test "lanekeep trace clear with no files shows no-op message" {
  output=$("$LANEKEEP_DIR/bin/lanekeep-trace" clear)
  [[ "$output" == *"No trace files to clear"* ]]
}
