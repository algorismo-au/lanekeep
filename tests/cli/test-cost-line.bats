#!/usr/bin/env bats
# Tests for lanekeep-trace --summary {cost-line,json}
# Spec: specs/COST-LINE-EXPORTER.md
# v1 scope: current-session only — see "v1 Scope Constraint" in spec.

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TRACE_BIN="$LANEKEEP_DIR/bin/lanekeep-trace"

  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/sessions"
  STATE_FILE="$TEST_TMP/.lanekeep/state.json"
  SESSIONS_DIR="$TEST_TMP/.lanekeep/sessions"

  # Default: 14m elapsed, sonnet, modest token counts
  START_EPOCH=$(( $(date +%s) - 840 ))
}

# Helper: write a session-summary file (simulates a completed prior attempt).
# Args: session_id task_id model cost savings duration_seconds
_write_summary() {
  jq -n \
    --arg sid "$1" --arg tid "$2" --arg model "$3" \
    --argjson cost "$4" --argjson savings "$5" --argjson dur "$6" \
    '{
      version:1, session_id:$sid, task_id:$tid, model:$model,
      input_tokens:1000, output_tokens:500,
      cache_creation_input_tokens:0, cache_read_input_tokens:0,
      start_epoch:1700000000, end_epoch:(1700000000+$dur),
      duration_seconds:$dur, cost:$cost, cache_savings:$savings
    }' > "$SESSIONS_DIR/${1}.summary.json"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

# Helper: write state.json with the given token + model values.
# Args: input_tokens cache_creation cache_read output_tokens model task_id
_write_state() {
  jq -n \
    --argjson itoks "$1" --argjson cctoks "$2" --argjson crtoks "$3" \
    --argjson otoks "$4" --arg model "$5" --arg task_id "$6" \
    --argjson start "$START_EPOCH" \
    '{
      action_count:10, token_count:($itoks + $otoks),
      input_tokens:$itoks, output_tokens:$otoks,
      cache_creation_input_tokens:$cctoks, cache_read_input_tokens:$crtoks,
      total_events:30, start_epoch:$start,
      session_id:"test-session-001", lanekeep_session_id:"test-session-001",
      token_source:"transcript", task_id:$task_id, model:$model
    }' > "$STATE_FILE"
}

# --- AC 1: cost-line shape ---
@test "cost-line emits expected format" {
  _write_state 40000 5000 15000 10000 "claude-sonnet-4-6" "T-1"
  run "$TRACE_BIN" --summary cost-line
  [ "$status" -eq 0 ]
  # $X.XX · 1 attempt · 14m · sonnet-4.6
  [[ "$output" =~ ^\$[0-9]+\.[0-9]+\ ·\ 1\ attempt\ ·\ 14m\ ·\ sonnet-4\.6$ ]]
}

# --- AC 2: --with-savings adds segment after cost ---
@test "--with-savings inserts savings segment between cost and attempts" {
  _write_state 40000 5000 15000 10000 "claude-sonnet-4-6" "T-1"
  run "$TRACE_BIN" --summary cost-line --with-savings
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^\$[0-9]+\.[0-9]+\ ·\ saved\ \$[0-9]+\.[0-9]+\ ·\ 1\ attempt\ ·\  ]]
}

# --- AC 3: --with-savings omits segment when savings == 0 ---
@test "--with-savings omits savings when cache_read_tokens=0" {
  _write_state 40000 0 0 10000 "claude-sonnet-4-6" "T-1"
  run "$TRACE_BIN" --summary cost-line --with-savings
  [ "$status" -eq 0 ]
  [[ "$output" != *"saved"* ]]
}

# --- AC 4: singular "1 attempt" not "1 attempts" ---
@test "single attempt uses singular form" {
  _write_state 1000 0 0 500 "claude-sonnet-4-6" "T-1"
  run "$TRACE_BIN" --summary cost-line
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 attempt · "* ]]
  [[ "$output" != *"1 attempts"* ]]
}

# --- AC 5: missing model → model segment omitted ---
@test "missing model omits model segment but keeps cost/attempts/duration" {
  _write_state 1000 0 0 500 "" "T-1"
  run "$TRACE_BIN" --summary cost-line
  [ "$status" -eq 0 ]
  # Expect 3 segments (cost, attempts, duration) — exactly 2 "·" separators
  sep_count=$(printf '%s' "$output" | grep -o '·' | wc -l)
  [ "$sep_count" -eq 2 ]
}

# --- AC 6: unknown model → cost falls back to $0.00 but line still prints ---
@test "unknown model produces \$0.00 cost without error" {
  _write_state 1000 0 0 500 "totally-made-up-model" "T-1"
  run "$TRACE_BIN" --summary cost-line
  [ "$status" -eq 0 ]
  [[ "$output" == "\$0.00 · "* ]]
}

# --- AC 7: no-data → exit 1, empty stdout, stderr message ---
@test "no state.json → exit 1 with empty stdout" {
  rm -f "$STATE_FILE"
  # Capture stdout-only so the stderr message doesn't pollute the assertion
  stdout=$("$TRACE_BIN" --summary cost-line 2>/dev/null; printf 'EXIT=%s' "$?")
  [[ "$stdout" == "EXIT=1" ]]
}

@test "empty state (zero activity) → exit 1" {
  _write_state 0 0 0 0 "" ""
  run "$TRACE_BIN" --summary cost-line
  [ "$status" -eq 1 ]
}

# --- AC 8: --task mismatch with no summaries → no-data ---
@test "--task with no matching session or summary → exit 1" {
  _write_state 1000 0 0 500 "claude-sonnet-4-6" "T-CURRENT"
  run "$TRACE_BIN" --summary cost-line --task T-OTHER
  [ "$status" -eq 1 ]
}

# --- AC 9: --task matching current state.task_id → works ---
@test "--task matching current task_id works like session scope" {
  _write_state 1000 0 0 500 "claude-sonnet-4-6" "T-MATCH"
  run "$TRACE_BIN" --summary cost-line --task T-MATCH
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 attempt"* ]]
}

# --- AC 10: env var LANEKEEP_TASK_ID drives scope ---
@test "LANEKEEP_TASK_ID env drives task scope when no flag given" {
  _write_state 1000 0 0 500 "claude-sonnet-4-6" "T-ENV"
  LANEKEEP_TASK_ID=T-ENV run "$TRACE_BIN" --summary cost-line
  [ "$status" -eq 0 ]
}

# --- AC 11: JSON output shape ---
@test "--summary json emits valid JSON with required fields" {
  _write_state 40000 5000 15000 10000 "claude-sonnet-4-6" "T-1"
  run "$TRACE_BIN" --summary json
  [ "$status" -eq 0 ]
  # Valid JSON
  printf '%s' "$output" | jq . >/dev/null
  # Required fields
  [ "$(printf '%s' "$output" | jq -r .scope)" = "session" ]
  [ "$(printf '%s' "$output" | jq -r .id)" = "test-session-001" ]
  [ "$(printf '%s' "$output" | jq '.cost > 0')" = "true" ]
  [ "$(printf '%s' "$output" | jq '.cache_savings >= 0')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r .attempts)" = "1" ]
  [ "$(printf '%s' "$output" | jq '.duration_seconds >= 800')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r '.models[0]')" = "sonnet-4.6" ]
}

# --- AC 12: JSON cache_savings always present (even when zero) ---
@test "JSON cache_savings field is always present" {
  _write_state 1000 0 0 500 "claude-sonnet-4-6" "T-1"
  run "$TRACE_BIN" --summary json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq 'has("cache_savings")')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r .cache_savings)" = "0" ]
}

# --- AC 13: JSON models is array, empty when no model ---
@test "JSON models is empty array when model missing" {
  _write_state 1000 0 0 500 "" "T-1"
  run "$TRACE_BIN" --summary json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq '.models | type')" = '"array"' ]
  [ "$(printf '%s' "$output" | jq '.models | length')" = "0" ]
}

# --- AC 14: unknown --summary mode exits 2 ---
@test "unknown --summary mode exits 2" {
  run "$TRACE_BIN" --summary banana
  [ "$status" -eq 2 ]
}

# --- AC 15: --summary with no mode prints usage to stderr, exits 2 ---
@test "--summary with no mode exits 2" {
  run "$TRACE_BIN" --summary
  [ "$status" -eq 2 ]
}

# --- AC 16: existing lanekeep-trace subcommands still work ---
@test "regression: lanekeep-trace --all still works after --summary wiring" {
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  echo '{"timestamp":"2026-06-25T00:00:00Z","tool_name":"Read","decision":"allow"}' \
    > "$TEST_TMP/.lanekeep/traces/test.jsonl"
  run "$TRACE_BIN" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Read"* ]]
}

# --- Unit tests for pure formatters (sourced directly) ---

@test "_normalize_model: claude-sonnet-4-6-20260101 → sonnet-4.6" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_normalize_model "claude-sonnet-4-6-20260101")" = "sonnet-4.6" ]
}

@test "_normalize_model: claude-opus-4-7 → opus-4.7" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_normalize_model "claude-opus-4-7")" = "opus-4.7" ]
}

@test "_normalize_model: claude-haiku-4-5-20251001 → haiku-4.5" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_normalize_model "claude-haiku-4-5-20251001")" = "haiku-4.5" ]
}

@test "_normalize_model: claude-opus-4-8 → opus-4.8" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_normalize_model "claude-opus-4-8")" = "opus-4.8" ]
}

@test "_normalize_model: claude-sonnet-5 → sonnet-5" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_normalize_model "claude-sonnet-5")" = "sonnet-5" ]
}

@test "_normalize_model: claude-fable-5 → fable-5" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_normalize_model "claude-fable-5")" = "fable-5" ]
}

@test "_normalize_model: gpt-4o-2024-08-06 → gpt-4o" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_normalize_model "gpt-4o-2024-08-06")" = "gpt-4o" ]
}

@test "_normalize_model: unknown shape passes through unchanged" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_normalize_model "custom-model-foo")" = "custom-model-foo" ]
}

@test "_join_models_capped: 5 models → first 3 + +2more" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  result=$(printf 'a\nb\nc\nd\ne\n' | cost_line::_join_models_capped)
  [ "$result" = "a+b+c+2more" ]
}

@test "_join_models_capped: 2 models → joined with +" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  result=$(printf 'sonnet-4.6\nopus-4.7\n' | cost_line::_join_models_capped)
  [ "$result" = "sonnet-4.6+opus-4.7" ]
}

@test "_fmt_duration: 38s / 14m / 1h22m" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_fmt_duration 38)" = "38s" ]
  [ "$(cost_line::_fmt_duration 840)" = "14m" ]
  [ "$(cost_line::_fmt_duration 4920)" = "1h22m" ]
}

@test "_fmt_cost: sub-cent uses 4 decimals, zero is \$0.00" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  [ "$(cost_line::_fmt_cost 0)" = "\$0.00" ]
  [ "$(cost_line::_fmt_cost 0.0084)" = "\$0.0084" ]
  [ "$(cost_line::_fmt_cost 0.43)" = "\$0.43" ]
  [ "$(cost_line::_fmt_cost 1.234)" = "\$1.23" ]
}

@test "_dedup_models: preserves chronological order, removes dupes" {
  source "$LANEKEEP_DIR/lib/cost-line.sh"
  result=$(printf 'claude-sonnet-4-6\nclaude-opus-4-7\nclaude-sonnet-4-6\n' | \
    cost_line::_dedup_models | tr '\n' ',')
  [ "$result" = "sonnet-4.6,opus-4.7," ]
}

# --- Cross-session aggregation ---------------------------------------------

@test "task scope: 2 archived attempts + current session aggregates to 3 attempts" {
  _write_summary "20260101-100000-1" "T-99" "claude-sonnet-4-6" 0.150 0.020 600
  _write_summary "20260101-110000-2" "T-99" "claude-opus-4-7"   0.300 0.050 500
  _write_state 2000 0 0 1000 "claude-sonnet-4-6" "T-99"
  run "$TRACE_BIN" --summary cost-line --task T-99
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 attempts"* ]]
  # Cost ~ 0.150 + 0.300 + current — strictly > 0.45
  [[ "$output" =~ \$0\.[4-9][0-9] ]]
  # Both models present, chronological
  [[ "$output" == *"sonnet-4.6+opus-4.7"* ]]
}

@test "task scope: filter excludes summaries for other tasks" {
  _write_summary "20260101-100000-1" "T-99"    "claude-sonnet-4-6" 0.999 0 100
  _write_summary "20260101-110000-2" "T-OTHER" "claude-opus-4-7"   9.999 0 100
  _write_state 0 0 0 0 "" ""   # no current activity → only summaries count
  run "$TRACE_BIN" --summary cost-line --task T-99
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 attempt"* ]]
  # Must not include T-OTHER's $9.99
  [[ "$output" != *"\$9."* ]]
  [[ "$output" != *"\$10."* ]]
}

@test "task scope: current session NOT double-counted when its summary also exists" {
  _write_summary "test-session-001" "T-99" "claude-sonnet-4-6" 0.100 0 100
  _write_state 1000 0 0 500 "claude-sonnet-4-6" "T-99"
  run "$TRACE_BIN" --summary cost-line --task T-99
  [ "$status" -eq 0 ]
  # Current session has session_id=test-session-001; the summary with the
  # same session_id should be skipped (current session takes precedence)
  [[ "$output" == *"1 attempt"* ]]
}

@test "task scope: no archived match AND no current match → exit 1" {
  _write_state 1000 0 0 500 "claude-sonnet-4-6" "T-X"
  run "$TRACE_BIN" --summary cost-line --task T-MISSING
  [ "$status" -eq 1 ]
}

@test "task scope: JSON output reports total attempts and resolved id" {
  _write_summary "20260101-100000-1" "T-99" "claude-sonnet-4-6" 0.150 0.020 600
  _write_summary "20260101-110000-2" "T-99" "claude-opus-4-7"   0.300 0.050 500
  _write_state 2000 0 0 1000 "claude-sonnet-4-6" "T-99"
  run "$TRACE_BIN" --summary json --task T-99
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq . >/dev/null
  [ "$(printf '%s' "$output" | jq -r .scope)" = "task" ]
  [ "$(printf '%s' "$output" | jq -r .id)" = "T-99" ]
  [ "$(printf '%s' "$output" | jq -r .attempts)" = "3" ]
  [ "$(printf '%s' "$output" | jq -r '.models | length')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.models[0]')" = "sonnet-4.6" ]
  [ "$(printf '%s' "$output" | jq -r '.models[1]')" = "opus-4.7" ]
}

@test "session scope: --session <archived-id> looks up summary file" {
  _write_summary "archived-only" "T-X" "claude-opus-4-7" 0.250 0.030 420
  _write_state 0 0 0 0 "" ""
  run "$TRACE_BIN" --summary cost-line --session archived-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 attempt"* ]]
  [[ "$output" == *"opus-4.7"* ]]
  [[ "$output" == *"7m"* ]]   # 420s = 7m
}

# --- Session-summary writer (cumulative_init) ------------------------------

@test "cumulative_init writes per-session summary for activity-having session" {
  source "$LANEKEEP_DIR/lib/cumulative.sh"

  # Simulate a previous session's state.json with model + tokens + task_id
  local prev_state="$TEST_TMP/.lanekeep/prev-state.json"
  jq -n --argjson s "$START_EPOCH" '{
    action_count:5, token_count:1500, input_tokens:1000, output_tokens:500,
    cache_creation_input_tokens:0, cache_read_input_tokens:0, total_events:10,
    start_epoch:$s, session_id:"finalized-session", task_id:"T-FIN",
    model:"claude-sonnet-4-6"
  }' > "$prev_state"

  LANEKEEP_STATE_FILE="$prev_state" \
  LANEKEEP_SESSIONS_DIR="$SESSIONS_DIR" \
  LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json" \
    cumulative_init

  local summary="$SESSIONS_DIR/finalized-session.summary.json"
  [ -f "$summary" ]
  [ "$(jq -r .session_id "$summary")" = "finalized-session" ]
  [ "$(jq -r .task_id "$summary")" = "T-FIN" ]
  [ "$(jq -r .model "$summary")" = "claude-sonnet-4-6" ]
  [ "$(jq -r .input_tokens "$summary")" = "1000" ]
  [ "$(jq '.cost > 0' "$summary")" = "true" ]
}

@test "cumulative_init does NOT write summary for zero-activity session" {
  source "$LANEKEEP_DIR/lib/cumulative.sh"

  local prev_state="$TEST_TMP/.lanekeep/prev-state.json"
  jq -n '{
    action_count:0, token_count:0, input_tokens:0, output_tokens:0,
    cache_creation_input_tokens:0, cache_read_input_tokens:0, total_events:0,
    start_epoch:1700000000, session_id:"empty-session", task_id:"", model:""
  }' > "$prev_state"

  LANEKEEP_STATE_FILE="$prev_state" \
  LANEKEEP_SESSIONS_DIR="$SESSIONS_DIR" \
  LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json" \
    cumulative_init

  [ ! -f "$SESSIONS_DIR/empty-session.summary.json" ]
}

@test "cumulative_init summary omits task_id field when empty" {
  source "$LANEKEEP_DIR/lib/cumulative.sh"

  local prev_state="$TEST_TMP/.lanekeep/prev-state.json"
  jq -n --argjson s "$START_EPOCH" '{
    action_count:5, token_count:1500, input_tokens:1000, output_tokens:500,
    cache_creation_input_tokens:0, cache_read_input_tokens:0, total_events:10,
    start_epoch:$s, session_id:"no-task-session", task_id:"",
    model:"claude-sonnet-4-6"
  }' > "$prev_state"

  LANEKEEP_STATE_FILE="$prev_state" \
  LANEKEEP_SESSIONS_DIR="$SESSIONS_DIR" \
  LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json" \
    cumulative_init

  local summary="$SESSIONS_DIR/no-task-session.summary.json"
  [ -f "$summary" ]
  [ "$(jq 'has("task_id")' "$summary")" = "false" ]
}
