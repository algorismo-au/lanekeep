#!/usr/bin/env bats
# Tests for eval-session-patterns.sh (Tier 2.6)

setup() {
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_CONFIG_FILE="/nonexistent/lanekeep.json"
  export _NOW_EPOCH=1000000   # fixed epoch so time window tests are deterministic
  unset _CFG_SESSION_EVASION_THRESHOLD _CFG_SESSION_DENIAL_CLUSTER _CFG_SESSION_TIME_WINDOW

  # Derive the events file path the same way the evaluator does
  EVENTS_FILE="${LANEKEEP_STATE_FILE%.json}_events.jsonl"

  source "$BATS_TEST_DIRNAME/../../lib/eval-session-patterns.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# Helper: write N deny events for a given tool, all within the time window
_write_deny_events() {
  local tool="$1"
  local count="$2"
  local epoch="${3:-999990}"   # recent, within default 120s window of _NOW_EPOCH=1000000
  for _ in $(seq 1 "$count"); do
    printf '{"tool":"%s","decision":"deny","epoch":%s,"hash":"aabbccdd"}\n' "$tool" "$epoch" >> "$EVENTS_FILE"
  done
}

# Helper: write N allow events for a given tool
_write_allow_events() {
  local tool="$1"
  local count="$2"
  for _ in $(seq 1 "$count"); do
    printf '{"tool":"%s","decision":"allow","epoch":999990,"hash":"aabbccdd"}\n' "$tool" >> "$EVENTS_FILE"
  done
}

# AC1: No events file — pass
@test "session_pattern_eval passes when no events file exists" {
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

@test "session_pattern_eval leaves SESSION_PATTERN_PASSED=true when no events file" {
  session_pattern_eval "Bash" '{}'
  [ "$SESSION_PATTERN_PASSED" = "true" ]
}

# AC2: Empty events file — pass
@test "session_pattern_eval passes with empty events file" {
  touch "$EVENTS_FILE"
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC3: Denial clustering — 5 denials in window triggers (default threshold=5)
@test "session_pattern_eval returns 1 when denial count meets cluster threshold" {
  _write_deny_events "Bash" 5
  run session_pattern_eval "AnyTool" '{}'
  [ "$status" -eq 1 ]
}

@test "session_pattern_eval sets SESSION_PATTERN_PASSED=false on denial cluster" {
  _write_deny_events "Bash" 5
  session_pattern_eval "AnyTool" '{}' || true
  [ "$SESSION_PATTERN_PASSED" = "false" ]
}

@test "session_pattern_eval reason mentions denial clustering" {
  _write_deny_events "Bash" 5
  session_pattern_eval "AnyTool" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"denial clustering"* ]]
}

@test "session_pattern_eval reason mentions CWE-799 on denial cluster" {
  _write_deny_events "Bash" 5
  session_pattern_eval "AnyTool" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"CWE-799"* ]]
}

# AC4: 4 denials — below threshold, passes
@test "session_pattern_eval passes with 4 denials (below cluster threshold of 5)" {
  _write_deny_events "Bash" 4
  run session_pattern_eval "AnyTool" '{}'
  [ "$status" -eq 0 ]
}

# AC5: Evasion — same tool denied 3+ times and current tool matches (default threshold=3)
@test "session_pattern_eval returns 1 on evasion when calling denied tool again" {
  _write_deny_events "Bash" 3
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "session_pattern_eval sets SESSION_PATTERN_PASSED=false on evasion" {
  _write_deny_events "Bash" 3
  session_pattern_eval "Bash" '{}' || true
  [ "$SESSION_PATTERN_PASSED" = "false" ]
}

@test "session_pattern_eval reason mentions evasion" {
  _write_deny_events "Bash" 3
  session_pattern_eval "Bash" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"vasion"* ]]
}

# AC6: Evasion does NOT trigger when calling a different tool
@test "session_pattern_eval passes when calling different tool despite Bash being denied 3 times" {
  _write_deny_events "Bash" 3
  run session_pattern_eval "Edit" '{}'
  [ "$status" -eq 0 ]
}

# AC7: Stale events (outside time window) are ignored
@test "session_pattern_eval ignores deny events outside the time window" {
  # epoch=100 is well outside the 120s window of _NOW_EPOCH=1000000
  for _ in $(seq 1 10); do
    printf '{"tool":"Bash","decision":"deny","epoch":100,"hash":"aabbccdd"}\n' >> "$EVENTS_FILE"
  done
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC8: Config overrides via _CFG_* env vars
@test "session_pattern_eval respects custom evasion threshold" {
  export _CFG_SESSION_EVASION_THRESHOLD=2
  export _CFG_SESSION_DENIAL_CLUSTER=5
  export _CFG_SESSION_TIME_WINDOW=120
  _write_deny_events "Bash" 2
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "session_pattern_eval respects custom denial cluster threshold" {
  export _CFG_SESSION_EVASION_THRESHOLD=3
  export _CFG_SESSION_DENIAL_CLUSTER=3
  export _CFG_SESSION_TIME_WINDOW=120
  _write_deny_events "Edit" 3
  run session_pattern_eval "AnyTool" '{}'
  [ "$status" -eq 1 ]
}

# AC9: Allows with only allow events (no denials)
@test "session_pattern_eval passes when all events are allow decisions" {
  _write_allow_events "Bash" 10
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}
