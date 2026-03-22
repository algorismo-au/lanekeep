#!/usr/bin/env bats
# Tests for insights metrics: session vs all-time correctness

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
}

teardown() {
  # Kill any lingering server processes
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null || true
  rm -rf "$TEST_TMP" ; return 0
}

# Helper: start server and wait for it to be ready
start_server() {
  local port="$1"
  "$LANEKEEP_DIR/ui/server.py" --port "$port" --config "$LANEKEEP_CONFIG_FILE" --project-dir "$TEST_TMP" &
  SERVER_PID=$!
  # Wait for server to start (up to 3 seconds)
  local retries=30
  while [ $retries -gt 0 ]; do
    if curl -sf "http://127.0.0.1:$port/api/status" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
    retries=$((retries - 1))
  done
  return 1
}

@test "Events count uses total_events not action_count" {
  # Create state.json where total_events != action_count
  # total_events counts Pre+Post, action_count counts Pre only
  printf '{"action_count":5,"total_events":10,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"test"}\n' \
    "$(date +%s)" > "$TEST_TMP/.lanekeep/state.json"

  local port
  port=$((RANDOM % 10000 + 20000))
  start_server "$port"

  local status
  status=$(curl -s "http://127.0.0.1:$port/api/status")

  # budget.events should be 10 (total_events), not 5 (action_count)
  local events
  events=$(printf '%s' "$status" | jq -r '.budget.events')
  [ "$events" -eq 10 ]
}

@test "Session trace returns only current session decisions" {
  local now_epoch
  now_epoch=$(date +%s)

  # Create state pointing to session-B
  printf '{"action_count":2,"total_events":2,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"session-B"}\n' \
    "$now_epoch" > "$TEST_TMP/.lanekeep/state.json"

  # Create old session trace file
  printf '{"timestamp":"2025-01-01T00:00:01Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":5}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-A.jsonl"
  printf '{"timestamp":"2025-01-01T00:00:02Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":3}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-A.jsonl"

  # Create current session trace file
  printf '{"timestamp":"2025-01-02T00:00:01Z","tool_name":"Read","decision":"allow","event_type":"PreToolUse","latency_ms":2}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-B.jsonl"
  printf '{"timestamp":"2025-01-02T00:00:02Z","tool_name":"Write","decision":"deny","event_type":"PreToolUse","latency_ms":4}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-B.jsonl"

  local port
  port=$((RANDOM % 10000 + 20000))
  start_server "$port"

  local status
  status=$(curl -s "http://127.0.0.1:$port/api/status")

  # Session should have 1 deny, 1 allow (from session-B only)
  local sess_deny sess_allow
  sess_deny=$(printf '%s' "$status" | jq -r '.session.decisions.deny')
  sess_allow=$(printf '%s' "$status" | jq -r '.session.decisions.allow')
  [ "$sess_deny" -eq 1 ]
  [ "$sess_allow" -eq 1 ]

  # Session should have top_denied_tools and top_evaluators
  [ "$(printf '%s' "$status" | jq -r '.session | has("top_denied_tools")')" = "true" ]
  [ "$(printf '%s' "$status" | jq -r '.session | has("latency_values")')" = "true" ]
}

@test "All-time computed from multiple trace files" {
  local now_epoch
  now_epoch=$(date +%s)

  printf '{"action_count":1,"total_events":1,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"session-B"}\n' \
    "$now_epoch" > "$TEST_TMP/.lanekeep/state.json"

  # Session A trace: 2 denies
  printf '{"timestamp":"2025-01-01T00:00:01Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":5,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-A.jsonl"
  printf '{"timestamp":"2025-01-01T00:00:02Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":3,"evaluators":[{"name":"HardBlock","passed":false}]}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-A.jsonl"

  # Session B trace: 1 allow, 1 deny
  printf '{"timestamp":"2025-01-02T00:00:01Z","tool_name":"Read","decision":"allow","event_type":"PreToolUse","latency_ms":2}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-B.jsonl"
  printf '{"timestamp":"2025-01-02T00:00:02Z","tool_name":"Write","decision":"deny","event_type":"PreToolUse","latency_ms":4,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-B.jsonl"

  local port
  port=$((RANDOM % 10000 + 20000))
  start_server "$port"

  local status
  status=$(curl -s "http://127.0.0.1:$port/api/status")

  # All-time: 3 deny + 1 allow = 4 total decisions
  local cum_deny cum_allow
  cum_deny=$(printf '%s' "$status" | jq -r '.cumulative.decisions.deny')
  cum_allow=$(printf '%s' "$status" | jq -r '.cumulative.decisions.allow')
  [ "$cum_deny" -eq 3 ]
  [ "$cum_allow" -eq 1 ]

  # All-time top_denied_tools: Bash=2, Write=1
  local bash_count
  bash_count=$(printf '%s' "$status" | jq -r '.cumulative.top_denied_tools.Bash')
  [ "$bash_count" -eq 2 ]

  # All-time top_evaluators: RuleEngine=2, HardBlock=1
  local rule_count
  rule_count=$(printf '%s' "$status" | jq -r '.cumulative.top_evaluators.RuleEngine')
  [ "$rule_count" -eq 2 ]

  # All-time latency
  local lat_count
  lat_count=$(printf '%s' "$status" | jq -r '.cumulative.latency.count')
  [ "$lat_count" -eq 4 ]
}

@test "Session boundary: new session trace excludes old entries" {
  local now_epoch
  now_epoch=$(date +%s)

  # Point state to session-C
  printf '{"action_count":1,"total_events":1,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"session-C"}\n' \
    "$now_epoch" > "$TEST_TMP/.lanekeep/state.json"

  # Old sessions with denials
  printf '{"timestamp":"2025-01-01T00:00:01Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":5}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-A.jsonl"
  printf '{"timestamp":"2025-01-02T00:00:01Z","tool_name":"Write","decision":"deny","event_type":"PreToolUse","latency_ms":3}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-B.jsonl"

  # Current session: only allows
  printf '{"timestamp":"2025-01-03T00:00:01Z","tool_name":"Read","decision":"allow","event_type":"PreToolUse","latency_ms":2}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-C.jsonl"

  local port
  port=$((RANDOM % 10000 + 20000))
  start_server "$port"

  local status
  status=$(curl -s "http://127.0.0.1:$port/api/status")

  # Session should have 0 denies (only session-C's entries)
  local sess_deny sess_allow
  sess_deny=$(printf '%s' "$status" | jq -r '.session.decisions.deny')
  sess_allow=$(printf '%s' "$status" | jq -r '.session.decisions.allow')
  [ "$sess_deny" -eq 0 ]
  [ "$sess_allow" -eq 1 ]

  # All-time should have 2 denies + 1 allow
  local cum_deny cum_allow
  cum_deny=$(printf '%s' "$status" | jq -r '.cumulative.decisions.deny')
  cum_allow=$(printf '%s' "$status" | jq -r '.cumulative.decisions.allow')
  [ "$cum_deny" -eq 2 ]
  [ "$cum_allow" -eq 1 ]
}

@test "Session widget values match only current session trace" {
  local now_epoch
  now_epoch=$(date +%s)

  # 3 sessions with distinct deny patterns:
  #   A: Bash denied twice (RuleEngine, HardBlock), latencies 100, 200
  #   B: Write denied once (RuleEngine), Read allowed, latencies 50, 300
  #   C (current): WebFetch denied once (RuleEngine), Edit allowed twice, latencies 150, 80, 400

  # --- Session A ---
  printf '{"timestamp":"2025-01-01T00:00:01Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":100,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-A.jsonl"
  printf '{"timestamp":"2025-01-01T00:00:02Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":200,"evaluators":[{"name":"HardBlock","passed":false}]}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-A.jsonl"

  # --- Session B ---
  printf '{"timestamp":"2025-01-02T00:00:01Z","tool_name":"Write","decision":"deny","event_type":"PreToolUse","latency_ms":50,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-B.jsonl"
  printf '{"timestamp":"2025-01-02T00:00:02Z","tool_name":"Read","decision":"allow","event_type":"PreToolUse","latency_ms":300}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-B.jsonl"

  # --- Session C (current) ---
  printf '{"timestamp":"2025-01-03T00:00:01Z","tool_name":"WebFetch","decision":"deny","event_type":"PreToolUse","latency_ms":150,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-C.jsonl"
  printf '{"timestamp":"2025-01-03T00:00:02Z","tool_name":"Edit","decision":"allow","event_type":"PreToolUse","latency_ms":80}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-C.jsonl"
  printf '{"timestamp":"2025-01-03T00:00:03Z","tool_name":"Edit","decision":"allow","event_type":"PreToolUse","latency_ms":400}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-C.jsonl"

  # State points to session-C
  printf '{"action_count":3,"total_events":3,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"session-C"}\n' \
    "$now_epoch" > "$TEST_TMP/.lanekeep/state.json"

  local port
  port=$((RANDOM % 10000 + 20000))
  start_server "$port"

  local status
  status=$(curl -s "http://127.0.0.1:$port/api/status")

  # --- Session: only session-C data ---

  # Decisions: 1 deny, 2 allow
  [ "$(printf '%s' "$status" | jq -r '.session.decisions.deny')" -eq 1 ]
  [ "$(printf '%s' "$status" | jq -r '.session.decisions.allow')" -eq 2 ]

  # Top denied tools: only WebFetch:1 (not Bash, not Write)
  [ "$(printf '%s' "$status" | jq -r '.session.top_denied_tools.WebFetch')" -eq 1 ]
  [ "$(printf '%s' "$status" | jq -r '.session.top_denied_tools | length')" -eq 1 ]

  # Top evaluators: only RuleEngine:1 (not HardBlock — that was session A)
  [ "$(printf '%s' "$status" | jq -r '.session.top_evaluators.RuleEngine')" -eq 1 ]
  [ "$(printf '%s' "$status" | jq -r '.session.top_evaluators | length')" -eq 1 ]

  # Latency values: exactly [150, 80, 400] — session C only
  [ "$(printf '%s' "$status" | jq -r '.session.latency_values | length')" -eq 3 ]
  [ "$(printf '%s' "$status" | jq -r '.session.latency_values | sort | .[0]')" -eq 80 ]
  [ "$(printf '%s' "$status" | jq -r '.session.latency_values | sort | .[1]')" -eq 150 ]
  [ "$(printf '%s' "$status" | jq -r '.session.latency_values | sort | .[2]')" -eq 400 ]
}

@test "All-time widget values aggregate across all sessions" {
  local now_epoch
  now_epoch=$(date +%s)

  # Same 3-session layout as session test above
  printf '{"timestamp":"2025-01-01T00:00:01Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":100,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-A.jsonl"
  printf '{"timestamp":"2025-01-01T00:00:02Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":200,"evaluators":[{"name":"HardBlock","passed":false}]}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-A.jsonl"

  printf '{"timestamp":"2025-01-02T00:00:01Z","tool_name":"Write","decision":"deny","event_type":"PreToolUse","latency_ms":50,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-B.jsonl"
  printf '{"timestamp":"2025-01-02T00:00:02Z","tool_name":"Read","decision":"allow","event_type":"PreToolUse","latency_ms":300}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-B.jsonl"

  printf '{"timestamp":"2025-01-03T00:00:01Z","tool_name":"WebFetch","decision":"deny","event_type":"PreToolUse","latency_ms":150,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-C.jsonl"
  printf '{"timestamp":"2025-01-03T00:00:02Z","tool_name":"Edit","decision":"allow","event_type":"PreToolUse","latency_ms":80}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-C.jsonl"
  printf '{"timestamp":"2025-01-03T00:00:03Z","tool_name":"Edit","decision":"allow","event_type":"PreToolUse","latency_ms":400}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-C.jsonl"

  printf '{"action_count":3,"total_events":3,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"session-C"}\n' \
    "$now_epoch" > "$TEST_TMP/.lanekeep/state.json"

  local port
  port=$((RANDOM % 10000 + 20000))
  start_server "$port"

  local status
  status=$(curl -s "http://127.0.0.1:$port/api/status")

  # --- All-time: aggregated across A + B + C ---

  # Decisions: 4 deny (2 A + 1 B + 1 C), 3 allow (1 B + 2 C)
  [ "$(printf '%s' "$status" | jq -r '.cumulative.decisions.deny')" -eq 4 ]
  [ "$(printf '%s' "$status" | jq -r '.cumulative.decisions.allow')" -eq 3 ]

  # Top denied tools: Bash=2, Write=1, WebFetch=1 (3 distinct tools)
  [ "$(printf '%s' "$status" | jq -r '.cumulative.top_denied_tools.Bash')" -eq 2 ]
  [ "$(printf '%s' "$status" | jq -r '.cumulative.top_denied_tools.Write')" -eq 1 ]
  [ "$(printf '%s' "$status" | jq -r '.cumulative.top_denied_tools.WebFetch')" -eq 1 ]
  [ "$(printf '%s' "$status" | jq -r '.cumulative.top_denied_tools | length')" -eq 3 ]

  # Top evaluators: RuleEngine=3 (A+B+C each have 1), HardBlock=1 (A only)
  [ "$(printf '%s' "$status" | jq -r '.cumulative.top_evaluators.RuleEngine')" -eq 3 ]
  [ "$(printf '%s' "$status" | jq -r '.cumulative.top_evaluators.HardBlock')" -eq 1 ]
  [ "$(printf '%s' "$status" | jq -r '.cumulative.top_evaluators | length')" -eq 2 ]

  # Latency: 7 entries total, sum = 100+200+50+300+150+80+400 = 1280, max = 400
  [ "$(printf '%s' "$status" | jq -r '.cumulative.latency.count')" -eq 7 ]
  [ "$(printf '%s' "$status" | jq -r '.cumulative.latency.sum_ms')" -eq 1280 ]
  [ "$(printf '%s' "$status" | jq -r '.cumulative.latency.max_ms')" -eq 400 ]
}

@test "Session and all-time values are consistent: session is subset of all-time" {
  local now_epoch
  now_epoch=$(date +%s)

  # Session A: Bash denied (RuleEngine)
  printf '{"timestamp":"2025-01-01T00:00:01Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":100,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-A.jsonl"

  # Session B (current): Bash denied (RuleEngine), Read allowed
  printf '{"timestamp":"2025-01-02T00:00:01Z","tool_name":"Bash","decision":"deny","event_type":"PreToolUse","latency_ms":200,"evaluators":[{"name":"RuleEngine","passed":false}]}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-B.jsonl"
  printf '{"timestamp":"2025-01-02T00:00:02Z","tool_name":"Read","decision":"allow","event_type":"PreToolUse","latency_ms":50}\n' \
    >> "$TEST_TMP/.lanekeep/traces/session-B.jsonl"

  printf '{"action_count":2,"total_events":2,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"session-B"}\n' \
    "$now_epoch" > "$TEST_TMP/.lanekeep/state.json"

  local port
  port=$((RANDOM % 10000 + 20000))
  start_server "$port"

  local status
  status=$(curl -s "http://127.0.0.1:$port/api/status")

  # Session deny <= all-time deny
  local sess_deny cum_deny
  sess_deny=$(printf '%s' "$status" | jq -r '.session.decisions.deny')
  cum_deny=$(printf '%s' "$status" | jq -r '.cumulative.decisions.deny')
  [ "$sess_deny" -eq 1 ]
  [ "$cum_deny" -eq 2 ]
  [ "$sess_deny" -le "$cum_deny" ]

  # Session denied tool count for Bash <= all-time
  local sess_bash cum_bash
  sess_bash=$(printf '%s' "$status" | jq -r '.session.top_denied_tools.Bash')
  cum_bash=$(printf '%s' "$status" | jq -r '.cumulative.top_denied_tools.Bash')
  [ "$sess_bash" -eq 1 ]
  [ "$cum_bash" -eq 2 ]
  [ "$sess_bash" -le "$cum_bash" ]

  # Session evaluator count <= all-time
  local sess_rule cum_rule
  sess_rule=$(printf '%s' "$status" | jq -r '.session.top_evaluators.RuleEngine')
  cum_rule=$(printf '%s' "$status" | jq -r '.cumulative.top_evaluators.RuleEngine')
  [ "$sess_rule" -eq 1 ]
  [ "$cum_rule" -eq 2 ]
  [ "$sess_rule" -le "$cum_rule" ]

  # Session latency count <= all-time latency count
  local sess_lat_count cum_lat_count
  sess_lat_count=$(printf '%s' "$status" | jq -r '.session.latency_values | length')
  cum_lat_count=$(printf '%s' "$status" | jq -r '.cumulative.latency.count')
  [ "$sess_lat_count" -eq 2 ]
  [ "$cum_lat_count" -eq 3 ]
  [ "$sess_lat_count" -le "$cum_lat_count" ]

  # Session max latency <= all-time max latency
  local sess_max cum_max
  sess_max=$(printf '%s' "$status" | jq -r '.session.latency_values | max')
  cum_max=$(printf '%s' "$status" | jq -r '.cumulative.latency.max_ms')
  [ "$sess_max" -eq 200 ]
  [ "$cum_max" -eq 200 ]
  [ "$sess_max" -le "$cum_max" ]
}

@test "cumulative_record no longer called from handler" {
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-session"

  printf '{"action_count":0,"total_events":0,"token_count":0,"input_tokens":0,"output_tokens":0,"start_epoch":%d,"session_id":"test-session"}\n' \
    "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  # Create empty cumulative with counters only (new schema)
  printf '{"version":1,"updated_at":"","total_sessions":0,"total_events":0,"total_actions":0,"total_tokens":0,"total_input_tokens":0,"total_output_tokens":0,"total_time_seconds":0}\n' \
    > "$LANEKEEP_CUMULATIVE_FILE"

  # Run handler
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"test-session"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]

  # cumulative.json should NOT have decisions/top_denied_tools fields
  # (cumulative_record is no longer called)
  local has_decisions
  has_decisions=$(jq 'has("decisions")' "$LANEKEEP_CUMULATIVE_FILE")
  [ "$has_decisions" = "false" ]
}
