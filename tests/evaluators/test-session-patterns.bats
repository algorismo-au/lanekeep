#!/usr/bin/env bats
# Tests for eval-session-patterns.sh (Tier 2.6)

setup() {
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_CONFIG_FILE="/nonexistent/lanekeep.json"
  export _NOW_EPOCH=1000000   # fixed epoch so time window tests are deterministic
  unset _CFG_SESSION_EVASION_THRESHOLD _CFG_SESSION_DENIAL_CLUSTER _CFG_SESSION_TIME_WINDOW
  unset SESSION_ID  # legacy fixtures without sid field match on empty current_sid

  # Derive the events file path the same way the evaluator does
  EVENTS_FILE="${LANEKEEP_STATE_FILE%.json}_events.jsonl"

  source "$BATS_TEST_DIRNAME/../../lib/eval-session-patterns.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# Helper: write N deny events for a given tool, all within the time window
# Optional 4th arg sid — when empty, writes legacy-style events without the sid field
_write_deny_events() {
  local tool="$1"
  local count="$2"
  local epoch="${3:-999990}"   # recent, within default 120s window of _NOW_EPOCH=1000000
  local sid="${4:-}"
  for _ in $(seq 1 "$count"); do
    if [ -n "$sid" ]; then
      printf '{"tool":"%s","decision":"deny","epoch":%s,"hash":"aabbccdd","sid":"%s"}\n' "$tool" "$epoch" "$sid" >> "$EVENTS_FILE"
    else
      printf '{"tool":"%s","decision":"deny","epoch":%s,"hash":"aabbccdd"}\n' "$tool" "$epoch" >> "$EVENTS_FILE"
    fi
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

# AC10: SESSION_PATTERN_DECISION is "ask" on clustering failure
@test "session_pattern_eval sets SESSION_PATTERN_DECISION=ask on denial cluster" {
  _write_deny_events "Bash" 5
  session_pattern_eval "AnyTool" '{}' || true
  [ "$SESSION_PATTERN_DECISION" = "ask" ]
}

# AC11: SESSION_PATTERN_DECISION is "ask" on evasion failure
@test "session_pattern_eval sets SESSION_PATTERN_DECISION=ask on evasion" {
  _write_deny_events "Bash" 3
  session_pattern_eval "Bash" '{}' || true
  [ "$SESSION_PATTERN_DECISION" = "ask" ]
}

# AC12: Clustering fires before evasion when both conditions met (5+ same-tool denials)
# Clustering check runs first in the evaluator; reason must mention clustering, not evasion
@test "session_pattern_eval triggers clustering reason (not evasion) when 5 same-tool denials" {
  _write_deny_events "Bash" 5
  session_pattern_eval "Bash" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"denial clustering"* ]]
  [[ "$SESSION_PATTERN_REASON" != *"Possible evasion"* ]]
}

# AC13: Mixed-tool clustering — 3 Bash + 2 Edit denials = 5 total → cluster triggers
@test "session_pattern_eval triggers clustering on mixed-tool denials reaching threshold" {
  _write_deny_events "Bash" 3
  _write_deny_events "Edit" 2
  run session_pattern_eval "Write" '{}'
  [ "$status" -eq 1 ]
}

@test "session_pattern_eval reason on mixed-tool cluster mentions denial clustering" {
  _write_deny_events "Bash" 3
  _write_deny_events "Edit" 2
  session_pattern_eval "Write" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"denial clustering"* ]]
}

# AC14: Mixed denials — 3 Bash + 1 Edit = 4 total, Bash meets evasion threshold;
# calling Bash triggers evasion (cluster not met)
@test "session_pattern_eval triggers evasion when 3 same-tool denials among 4 total" {
  _write_deny_events "Bash" 3
  _write_deny_events "Edit" 1
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "session_pattern_eval reason on partial mixed denials mentions evasion" {
  _write_deny_events "Bash" 3
  _write_deny_events "Edit" 1
  session_pattern_eval "Bash" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"vasion"* ]]
}

# AC15: Denials mixed with allows — allows do not inflate denial count
@test "session_pattern_eval does not count allow events toward denial cluster" {
  _write_allow_events "Bash" 10
  _write_deny_events "Bash" 4
  run session_pattern_eval "AnyTool" '{}'
  [ "$status" -eq 0 ]
}

# AC16: Stale denials do not contribute to evasion check
@test "session_pattern_eval does not flag evasion for denials outside time window" {
  # 3 stale Bash denials (outside 120s window) + calling Bash again = should pass
  for _ in $(seq 1 3); do
    printf '{"tool":"Bash","decision":"deny","epoch":100,"hash":"aabbccdd"}\n' >> "$EVENTS_FILE"
  done
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC17: session_pattern_record writes a valid JSONL line
@test "session_pattern_record appends a JSON line to the events file" {
  session_pattern_record "Bash" "deny" "999999" '{"command":"ls"}'
  [ -f "$EVENTS_FILE" ]
  local line
  line=$(cat "$EVENTS_FILE")
  [[ "$line" == *'"tool":"Bash"'* ]]
  [[ "$line" == *'"decision":"deny"'* ]]
  [[ "$line" == *'"epoch":999999'* ]]
}

@test "session_pattern_record includes a non-empty hash when input is provided" {
  session_pattern_record "Edit" "allow" "999999" '{"path":"/tmp/foo"}'
  local line
  line=$(cat "$EVENTS_FILE")
  # hash field must exist and be non-empty string
  [[ "$line" == *'"hash":"'* ]]
  local hash
  hash=$(printf '%s' "$line" | jq -r '.hash')
  [ -n "$hash" ]
}

@test "session_pattern_record writes empty hash when tool_input is empty" {
  session_pattern_record "Read" "allow" "999999" ""
  local hash
  hash=$(jq -r '.hash' "$EVENTS_FILE")
  [ "$hash" = "" ]
}

# AC18: Malformed JSONL lines in events file do not crash the evaluator
@test "session_pattern_eval survives malformed JSONL lines in events file" {
  printf 'not-json\n{"broken":\n{"tool":"Bash","decision":"deny","epoch":999990,"hash":"xx"}\n' >> "$EVENTS_FILE"
  run session_pattern_eval "Bash" '{}'
  # Should not crash (exit 1 is ok if denial triggered; non-zero from crash is not ok via assert)
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# AC19: _CFG_SESSION_TIME_WINDOW=0 treats all events as stale
@test "session_pattern_eval with time_window=0 ignores all events" {
  export _CFG_SESSION_EVASION_THRESHOLD=3
  export _CFG_SESSION_DENIAL_CLUSTER=5
  export _CFG_SESSION_TIME_WINDOW=0
  _write_deny_events "Bash" 10 999999  # 1s before _NOW_EPOCH=1000000; cutoff = 1000000-0 = 1000000 > 999999
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC20: cluster threshold reason includes count and window values
@test "session_pattern_eval clustering reason reports correct count and window" {
  _write_deny_events "Bash" 5
  session_pattern_eval "AnyTool" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"5 denials"* ]]
  [[ "$SESSION_PATTERN_REASON" == *"120s"* ]]
}

# AC21: evasion reason reports tool name and count
@test "session_pattern_eval evasion reason names the repeated tool" {
  _write_deny_events "Edit" 3
  session_pattern_eval "Edit" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"Edit"* ]]
  [[ "$SESSION_PATTERN_REASON" == *"3"* ]]
}

# AC22: _sp_json_escape is available without sourcing lanekeep-handler (Bug 4)
@test "_sp_json_escape is defined after sourcing evaluator alone" {
  run declare -F _sp_json_escape
  [ "$status" -eq 0 ]
  # Escapes quotes and backslashes
  local out
  out=$(_sp_json_escape 'a"b\c')
  [ "$out" = 'a\"b\\c' ]
}

# AC23: session_pattern_record writes the sid field (Bug 3)
@test "session_pattern_record writes sid field when provided" {
  session_pattern_record "Bash" "deny" "999999" '{}' "session-abc"
  local sid
  sid=$(jq -r '.sid' "$EVENTS_FILE")
  [ "$sid" = "session-abc" ]
}

@test "session_pattern_record writes empty sid field when omitted" {
  session_pattern_record "Bash" "deny" "999999" '{}'
  local sid
  sid=$(jq -r '.sid' "$EVENTS_FILE")
  [ "$sid" = "" ]
}

# AC24: session_id scoping — events from a different sid are ignored (Bug 3)
@test "session_pattern_eval ignores cluster denials from a different session_id" {
  _write_deny_events "Bash" 5 999990 "sid-A"
  export SESSION_ID="sid-B"
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

@test "session_pattern_eval counts cluster denials from the matching session_id" {
  _write_deny_events "Bash" 5 999990 "sid-A"
  export SESSION_ID="sid-A"
  run session_pattern_eval "AnyTool" '{}'
  [ "$status" -eq 1 ]
}

# AC25: legacy events without sid field are invisible when SESSION_ID is set (Bug 3)
@test "session_pattern_eval ignores legacy events (no sid field) when SESSION_ID is set" {
  _write_deny_events "Bash" 5   # legacy: no sid field in fixture
  export SESSION_ID="current-session"
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC26: legacy events are still counted when SESSION_ID is empty (backward compat)
@test "session_pattern_eval counts legacy events (no sid field) when SESSION_ID is empty" {
  _write_deny_events "Bash" 5   # legacy: no sid field
  # SESSION_ID is unset by setup() — legacy match is via empty current_sid
  run session_pattern_eval "AnyTool" '{}'
  [ "$status" -eq 1 ]
}

# AC27: evasion off-by-one fix — fires at (threshold)-th same-tool attempt (Bug 2)
# With threshold=3 and 2 prior Bash denials, the current Bash call is attempt #3 → trips
@test "session_pattern_eval fires evasion on threshold-th attempt (2 prior + current)" {
  _write_deny_events "Bash" 2
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "session_pattern_eval reason mentions evasion on threshold-th attempt" {
  _write_deny_events "Bash" 2
  session_pattern_eval "Bash" '{}' || true
  [[ "$SESSION_PATTERN_REASON" == *"vasion"* ]]
}

# AC28: evasion does NOT fire below threshold (1 prior + current = 2, below threshold=3)
@test "session_pattern_eval does not fire evasion below threshold (1 prior + current)" {
  _write_deny_events "Bash" 1
  run session_pattern_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC29: evasion still respects tool_name mismatch after off-by-one fix
@test "session_pattern_eval does not fire evasion when current tool differs (2 Bash + Edit call)" {
  _write_deny_events "Bash" 2
  run session_pattern_eval "Edit" '{}'
  [ "$status" -eq 0 ]
}
