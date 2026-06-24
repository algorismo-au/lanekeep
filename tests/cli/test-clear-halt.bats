#!/usr/bin/env bats
# Tests for: lanekeep clear-halt [--keep-counters]

LANEKEEP="$BATS_TEST_DIRNAME/../../bin/lanekeep"

# Canonical empty cumulative structure (mirrors _cumulative_empty in lib/cumulative.sh)
_empty_cumulative='{"version":1,"updated_at":"","total_sessions":0,"total_events":0,"total_actions":0,"total_tokens":0,"total_input_tokens":0,"total_output_tokens":0,"total_cache_creation_input_tokens":0,"total_cache_read_input_tokens":0,"total_time_seconds":0,"total_cost":0,"total_cache_savings":0}'

setup() {
  TMPDIR=$(mktemp -d)
  export LANEKEEP_DIR
  mkdir -p "$TMPDIR/.lanekeep"
  # Point both env vars into the tmpdir so no test touches real project state
  export LANEKEEP_CUMULATIVE_FILE="$TMPDIR/.lanekeep/cumulative.json"
  export LANEKEEP_HALTED_FILE="$TMPDIR/.lanekeep/halted.json"
  export PROJECT_DIR="$TMPDIR"
}

teardown() {
  rm -rf "$TMPDIR"
}

# --- helpers ---

_write_halt() {
  printf '{"halted":true,"halted_at":"2026-06-24T00:00:00Z","reason":"test","correlation_id":"","lanekeep_session_id":""}\n' \
    > "$LANEKEEP_HALTED_FILE"
}

_write_cumulative() {
  printf '{"version":1,"updated_at":"2026-06-24T00:00:00Z","total_sessions":3,"total_events":42,"total_actions":99,"total_tokens":12000,"total_input_tokens":10000,"total_output_tokens":2000,"total_cache_creation_input_tokens":500,"total_cache_read_input_tokens":300,"total_time_seconds":3600,"total_cost":0.15,"total_cache_savings":0.02}\n' \
    > "$LANEKEEP_CUMULATIVE_FILE"
}

# --- AC1: clear-halt removes halted.json AND zeros cumulative.json ---

@test "clear-halt removes halted.json" {
  _write_halt
  _write_cumulative

  run "$LANEKEEP" clear-halt
  [ "$status" -eq 0 ]
  [ ! -f "$LANEKEEP_HALTED_FILE" ]
}

@test "clear-halt resets cumulative counters to zero" {
  _write_halt
  _write_cumulative

  run "$LANEKEEP" clear-halt
  [ "$status" -eq 0 ]
  [ -f "$LANEKEEP_CUMULATIVE_FILE" ]

  # All numeric counters must be 0
  run jq -e '
    .total_sessions == 0 and
    .total_events == 0 and
    .total_actions == 0 and
    .total_tokens == 0 and
    .total_input_tokens == 0 and
    .total_output_tokens == 0 and
    .total_cache_creation_input_tokens == 0 and
    .total_cache_read_input_tokens == 0 and
    .total_time_seconds == 0 and
    .total_cost == 0 and
    .total_cache_savings == 0
  ' "$LANEKEEP_CUMULATIVE_FILE"
  [ "$status" -eq 0 ]
}

@test "clear-halt output mentions halt marker and cumulative file" {
  _write_halt
  _write_cumulative

  run "$LANEKEEP" clear-halt
  [ "$status" -eq 0 ]
  [[ "$output" == *"Halt marker removed"* ]]
  [[ "$output" == *"Cumulative counters reset"* ]]
}

@test "clear-halt creates zeroed cumulative.json when none existed" {
  _write_halt
  # no cumulative.json written

  run "$LANEKEEP" clear-halt
  [ "$status" -eq 0 ]
  [ -f "$LANEKEEP_CUMULATIVE_FILE" ]

  run jq -e '.total_actions == 0' "$LANEKEEP_CUMULATIVE_FILE"
  [ "$status" -eq 0 ]
}

# --- AC2: --keep-counters removes halted.json only ---

@test "clear-halt --keep-counters removes halted.json" {
  _write_halt
  _write_cumulative

  run "$LANEKEEP" clear-halt --keep-counters
  [ "$status" -eq 0 ]
  [ ! -f "$LANEKEEP_HALTED_FILE" ]
}

@test "clear-halt --keep-counters preserves cumulative.json contents" {
  _write_halt
  _write_cumulative

  run "$LANEKEEP" clear-halt --keep-counters
  [ "$status" -eq 0 ]
  [ -f "$LANEKEEP_CUMULATIVE_FILE" ]

  # Counters must be untouched (total_actions was 99)
  run jq -e '.total_actions == 99' "$LANEKEEP_CUMULATIVE_FILE"
  [ "$status" -eq 0 ]
}

@test "clear-halt --keep-counters does not mention counter reset" {
  _write_halt
  _write_cumulative

  run "$LANEKEEP" clear-halt --keep-counters
  [ "$status" -eq 0 ]
  [[ "$output" != *"Cumulative counters reset"* ]]
}

# --- AC3: idempotent when no halt marker present ---

@test "clear-halt with no halt marker exits 0" {
  # No halted.json written
  run "$LANEKEEP" clear-halt
  [ "$status" -eq 0 ]
}

@test "clear-halt with no halt marker prints informational note" {
  run "$LANEKEEP" clear-halt
  [ "$status" -eq 0 ]
  [[ "$output" == *"No halt marker present"* ]]
}

@test "clear-halt --keep-counters with no halt marker exits 0" {
  run "$LANEKEEP" clear-halt --keep-counters
  [ "$status" -eq 0 ]
  [[ "$output" == *"No halt marker present"* ]]
}

# --- AC4: error conditions ---

@test "clear-halt exits non-zero when cumulative dir is unwritable" {
  _write_halt
  # Make the .lanekeep directory read-only so cumulative.json.tmp cannot be written
  chmod 555 "$TMPDIR/.lanekeep"

  run "$LANEKEEP" clear-halt
  # Restore permissions before teardown
  chmod 755 "$TMPDIR/.lanekeep"
  [ "$status" -ne 0 ]
}

@test "clear-halt exits non-zero when halt marker dir is unwritable" {
  _write_halt
  # Make the .lanekeep directory read-only so rm of halted.json fails
  chmod 555 "$TMPDIR/.lanekeep"

  run "$LANEKEEP" clear-halt --keep-counters
  chmod 755 "$TMPDIR/.lanekeep"
  [ "$status" -ne 0 ]
}
