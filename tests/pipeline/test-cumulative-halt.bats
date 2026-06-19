#!/usr/bin/env bats
# AG-001 + stop signal: cumulative caps survive session_id cycling and
# emit halted.json when tripped. Per-session caps do NOT emit halt.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/cumulative.sh"
  source "$BATS_TEST_DIRNAME/../../lib/eval-budget.sh"

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_DIR="$TEST_TMP"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_TASKSPEC_FILE=""
  export LANEKEEP_SESSION_ID="ag001-sidecar"
  mkdir -p "$TEST_TMP/.lanekeep"
  unset _CFG_MAX_ACTIONS _CFG_TIMEOUT_SECONDS _CFG_MAX_TOKENS _CFG_MAX_INPUT_TOKENS \
        _CFG_MAX_OUTPUT_TOKENS _CFG_MAX_TOTAL_ACTIONS _CFG_MAX_TOTAL_INPUT_TOKENS \
        _CFG_MAX_TOTAL_OUTPUT_TOKENS _CFG_MAX_TOTAL_TOKENS _CFG_MAX_TOTAL_TIME \
        _CFG_MAX_COST _CFG_MAX_TOTAL_COST
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

# Run N actions under a given cc_session_id; returns after each call.
_drive_actions() {
  local n="$1" sid="$2" out="$3"
  local i
  for ((i=0; i<n; i++)); do
    budget_eval "{}" "" "" "input" "$sid" "false" >/dev/null 2>&1 || return $i
  done
  return "$n"
}

# AC1: Session-id cycling does NOT bypass max_total_actions
@test "cumulative cap holds across session_id cycling" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000, "max_total_actions": 8 } }
EOF

  # Session A: 5 actions, all under per-session limit
  for i in 1 2 3 4 5; do
    budget_eval "{}" "" "" "input" "session-A" "false"
    [ "$BUDGET_PASSED" = "true" ]
  done

  # Cycle to session B — finalizes session A's 5 actions into cumulative
  # Actions 1-3 of session B should pass (cum=5 + sess=1..3 = 6..8 <= 8)
  for i in 1 2 3; do
    budget_eval "{}" "" "" "input" "session-B" "false"
    [ "$BUDGET_PASSED" = "true" ]
  done

  # Action 4 of session B trips cumulative cap (5+4=9 > 8)
  budget_eval "{}" "" "" "input" "session-B" "false" || true
  [ "$BUDGET_PASSED" = "false" ]
  [[ "$BUDGET_REASON" == *"All-time action budget"* ]]
}

# AC2: Cumulative cap emits halted.json
@test "cumulative cap emits halted.json with reason + correlation_id" {
  export LANEKEEP_CORRELATION_ID="test-corr-001"
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000, "max_total_actions": 2 } }
EOF

  # 2 actions in session A, then cycle, then session B trips cumulative
  budget_eval "{}" "" "" "input" "session-A" "false"
  budget_eval "{}" "" "" "input" "session-A" "false"
  budget_eval "{}" "" "" "input" "session-B" "false" || true   # cum=2+1=3 > 2
  [ "$BUDGET_PASSED" = "false" ]

  local halted="$TEST_TMP/.lanekeep/halted.json"
  [ -f "$halted" ]
  [ "$(jq -r '.halted' "$halted")" = "true" ]
  [[ "$(jq -r '.reason' "$halted")" == *"All-time action budget"* ]]
  [ "$(jq -r '.correlation_id' "$halted")" = "test-corr-001" ]
  [ -n "$(jq -r '.halted_at' "$halted")" ]
}

# AC3: Per-session cap does NOT emit halted.json
@test "per-session cap trips but does not emit halt signal" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 2, "max_total_actions": 1000 } }
EOF

  budget_eval "{}" "" "" "input" "only-session" "false"
  budget_eval "{}" "" "" "input" "only-session" "false"
  budget_eval "{}" "" "" "input" "only-session" "false" || true
  [ "$BUDGET_PASSED" = "false" ]
  [[ "$BUDGET_REASON" == *"Action budget exceeded"* ]]
  [[ "$BUDGET_REASON" != *"All-time"* ]]

  [ ! -f "$TEST_TMP/.lanekeep/halted.json" ]
}

# AC4: LANEKEEP_HALTED_FILE env override redirects the halt file
@test "LANEKEEP_HALTED_FILE env var redirects halt signal" {
  export LANEKEEP_HALTED_FILE="$TEST_TMP/custom-halt.json"
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000, "max_total_actions": 0 } }
EOF

  budget_eval "{}" "" "" "input" "any-session" "false" || true
  [ "$BUDGET_PASSED" = "false" ]
  [ -f "$LANEKEEP_HALTED_FILE" ]
  [ ! -f "$TEST_TMP/.lanekeep/halted.json" ]
}

# AC5: cumulative cap denial sets cumulative_halted + halt_reason on the trace
@test "cumulative cap emits cumulative_halted + halt_reason on the trace event" {
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  mkdir -p "$(dirname "$LANEKEEP_TRACE_FILE")"
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000, "max_total_actions": 0 } }
EOF

  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"any-session"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "deny" ]

  local entry
  entry=$(tail -n1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$entry" | jq -r '.cumulative_halted')" = "true" ]
  [[ "$(printf '%s' "$entry" | jq -r '.halt_reason')" == *"All-time action budget"* ]]
}

# AC6: per-session cap denial does NOT set cumulative_halted on the trace
@test "per-session cap denial does not set cumulative_halted on the trace" {
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  mkdir -p "$(dirname "$LANEKEEP_TRACE_FILE")"
  # max_total_actions left null (defaults filtered out by minimal config below);
  # max_actions=0 trips per-session immediately.
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 0 } }
EOF

  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"only-session"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "deny" ]

  local entry
  entry=$(tail -n1 "$LANEKEEP_TRACE_FILE")
  # Field absent (or false) when the denial is per-session, not cumulative.
  [ "$(printf '%s' "$entry" | jq -r '.cumulative_halted // false')" = "false" ]
  [ "$(printf '%s' "$entry" | jq -r '.halt_reason // ""')" = "" ]
}
