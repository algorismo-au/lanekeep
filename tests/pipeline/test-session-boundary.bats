#!/usr/bin/env bats
# Tests for session boundary detection — CC session_id change resets budget

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-session-boundary"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

@test "Session boundary resets counters" {
  # Old session with 5 actions
  printf '{"action_count":5,"token_count":200,"input_tokens":200,"output_tokens":0,"total_events":5,"start_epoch":%d,"session_id":"old-session"}\n' \
    "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  # Send request with new session_id
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"new-session"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  # action_count should be 1 (reset + this action), not 6
  action_count=$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")
  [ "$action_count" -eq 1 ]

  # session_id should be updated
  sid=$(jq -r '.session_id' "$LANEKEEP_STATE_FILE")
  [ "$sid" = "new-session" ]
}

@test "Session boundary finalizes into cumulative.json" {
  # Old session with activity
  printf '{"action_count":5,"token_count":200,"input_tokens":150,"output_tokens":50,"total_events":5,"start_epoch":%d,"session_id":"old-session"}\n' \
    "$(($(date +%s) - 60))" > "$LANEKEEP_STATE_FILE"

  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"new-session"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  # cumulative.json should exist with finalized session
  [ -f "$LANEKEEP_CUMULATIVE_FILE" ]
  total_sessions=$(jq -r '.total_sessions' "$LANEKEEP_CUMULATIVE_FILE")
  total_actions=$(jq -r '.total_actions' "$LANEKEEP_CUMULATIVE_FILE")
  [ "$total_sessions" -ge 1 ]
  [ "$total_actions" -ge 5 ]

  # cumulative.json should have counters only — no qualitative fields
  # (decisions, top_denied_tools, etc. now come from traces)
  [ "$(jq 'has("decisions")' "$LANEKEEP_CUMULATIVE_FILE")" = "false" ]
  [ "$(jq 'has("top_denied_tools")' "$LANEKEEP_CUMULATIVE_FILE")" = "false" ]
  [ "$(jq 'has("top_evaluators")' "$LANEKEEP_CUMULATIVE_FILE")" = "false" ]
}

@test "Same session does not reset counters" {
  printf '{"action_count":5,"token_count":200,"input_tokens":200,"output_tokens":0,"total_events":5,"start_epoch":%d,"session_id":"same-session"}\n' \
    "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"same-session"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  # action_count should increment, not reset
  action_count=$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")
  [ "$action_count" -eq 6 ]
}

@test "Missing session_id preserves old behavior" {
  printf '{"action_count":5,"token_count":200,"input_tokens":200,"output_tokens":0,"total_events":5,"start_epoch":%d,"session_id":"existing"}\n' \
    "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  # No session_id in input
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  # Should increment normally
  action_count=$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")
  [ "$action_count" -eq 6 ]
}

@test "First call adopts session_id without finalization" {
  # State with no prior session_id and zero activity
  printf '{"action_count":0,"token_count":0,"input_tokens":0,"output_tokens":0,"total_events":0,"start_epoch":%d,"session_id":""}\n' \
    "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"first-session"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  # session_id adopted
  sid=$(jq -r '.session_id' "$LANEKEEP_STATE_FILE")
  [ "$sid" = "first-session" ]

  # No cumulative bump (no prior session to finalize)
  if [ -f "$LANEKEEP_CUMULATIVE_FILE" ]; then
    total_sessions=$(jq -r '.total_sessions' "$LANEKEEP_CUMULATIVE_FILE")
    [ "$total_sessions" -eq 0 ]
  fi
}

@test "Budget limit applies to new session after reset" {
  # Old session was at 99 actions, budget limit is 10
  cp "$LANEKEEP_DIR/tests/fixtures/taskspec-budget.json" "$LANEKEEP_TASKSPEC_FILE"
  printf '{"action_count":99,"token_count":5000,"input_tokens":3000,"output_tokens":2000,"total_events":99,"start_epoch":%d,"session_id":"old-session"}\n' \
    "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  # New session should be allowed (counter resets to 1, limit is 10)
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"new-session"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  action_count=$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")
  [ "$action_count" -eq 1 ]
}

@test "Full lifecycle: two sessions with cumulative rollup" {
  # Helper: send a Read tool call with a given session_id
  _send_request() {
    local sid="$1"
    echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"$sid\"}" \
      | "$LANEKEEP_DIR/bin/lanekeep-handler"
  }

  # Remove pre-seeded state — let the first call create it
  rm -f "$LANEKEEP_STATE_FILE"

  # --- Phase 1: Session A — 3 tool calls ---
  output=$(_send_request "session-A")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]

  output=$(_send_request "session-A")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]

  output=$(_send_request "session-A")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]

  # State: 3 actions, session-A
  [ "$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")" -eq 3 ]
  [ "$(jq -r '.session_id' "$LANEKEEP_STATE_FILE")" = "session-A" ]

  # No cumulative sessions yet (file may not exist, or total_sessions=0)
  if [ -f "$LANEKEEP_CUMULATIVE_FILE" ]; then
    [ "$(jq -r '.total_sessions' "$LANEKEEP_CUMULATIVE_FILE")" -eq 0 ]
  fi

  # --- Phase 2: Transition to Session B — triggers A finalization ---
  output=$(_send_request "session-B")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]

  # Cumulative: session A finalized
  [ -f "$LANEKEEP_CUMULATIVE_FILE" ]
  [ "$(jq -r '.total_sessions' "$LANEKEEP_CUMULATIVE_FILE")" -eq 1 ]
  [ "$(jq -r '.total_actions' "$LANEKEEP_CUMULATIVE_FILE")" -eq 3 ]

  # State reset for session B, 1 action counted
  [ "$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")" -eq 1 ]
  [ "$(jq -r '.session_id' "$LANEKEEP_STATE_FILE")" = "session-B" ]

  # --- Phase 3: Continue Session B — 2 more calls (no boundary) ---
  output=$(_send_request "session-B")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]

  output=$(_send_request "session-B")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]

  # State: 3 actions in session B
  [ "$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")" -eq 3 ]

  # Cumulative unchanged — still 1 session, 3 actions
  [ "$(jq -r '.total_sessions' "$LANEKEEP_CUMULATIVE_FILE")" -eq 1 ]
  [ "$(jq -r '.total_actions' "$LANEKEEP_CUMULATIVE_FILE")" -eq 3 ]

  # --- Phase 4: Transition to Session C — finalizes B ---
  output=$(_send_request "session-C")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]

  # Cumulative: 2 sessions finalized, 6 total actions (3 from A + 3 from B)
  [ "$(jq -r '.total_sessions' "$LANEKEEP_CUMULATIVE_FILE")" -eq 2 ]
  [ "$(jq -r '.total_actions' "$LANEKEEP_CUMULATIVE_FILE")" -eq 6 ]

  # State reset for session C
  [ "$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")" -eq 1 ]
  [ "$(jq -r '.session_id' "$LANEKEEP_STATE_FILE")" = "session-C" ]
}

@test "Session metrics use new session's trace file" {
  local now_epoch
  now_epoch=$(date +%s)

  # Create traces for two sessions
  printf '{"timestamp":"2025-01-01T00:00:01Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":5}\n' \
    > "$TEST_TMP/.lanekeep/traces/old-session.jsonl"
  printf '{"timestamp":"2025-01-02T00:00:01Z","tool_name":"Read","decision":"allow","event_type":"PreToolUse","latency_ms":2}\n' \
    > "$TEST_TMP/.lanekeep/traces/new-session.jsonl"

  # State points to new-session (write to .lanekeep/ where server reads it)
  printf '{"action_count":1,"total_events":1,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"new-session"}\n' \
    "$now_epoch" > "$TEST_TMP/.lanekeep/state.json"

  local port
  port=$((RANDOM % 10000 + 20000))
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null || true
  "$LANEKEEP_DIR/ui/server.py" --port "$port" --config "$LANEKEEP_CONFIG_FILE" --project-dir "$TEST_TMP" &
  SERVER_PID=$!
  local retries=30
  while [ $retries -gt 0 ]; do
    curl -sf "http://127.0.0.1:$port/api/status" >/dev/null 2>&1 && break
    sleep 0.1; retries=$((retries - 1))
  done

  local status
  status=$(curl -s "http://127.0.0.1:$port/api/status")

  # Session should use new-session's trace file
  local trace_file sess_deny sess_allow
  trace_file=$(printf '%s' "$status" | jq -r '.session.trace_file')
  [ "$trace_file" = "new-session.jsonl" ]

  # Session decisions: 0 deny, 1 allow (only new-session)
  sess_deny=$(printf '%s' "$status" | jq -r '.session.decisions.deny')
  sess_allow=$(printf '%s' "$status" | jq -r '.session.decisions.allow')
  [ "$sess_deny" -eq 0 ]
  [ "$sess_allow" -eq 1 ]

  kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""
}
