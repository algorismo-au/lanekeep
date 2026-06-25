#!/usr/bin/env bats
# Per-task budget scope: opt-in via LANEKEEP_TASK_ID, resets on TASK_ID
# change, independent of per-session and cumulative scopes, no halt signal.

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
  export LANEKEEP_SESSION_ID="task-budget-sidecar"
  mkdir -p "$TEST_TMP/.lanekeep"
  unset _CFG_MAX_ACTIONS _CFG_TIMEOUT_SECONDS _CFG_MAX_TOKENS _CFG_MAX_INPUT_TOKENS \
        _CFG_MAX_OUTPUT_TOKENS _CFG_MAX_TOTAL_ACTIONS _CFG_MAX_TOTAL_INPUT_TOKENS \
        _CFG_MAX_TOTAL_OUTPUT_TOKENS _CFG_MAX_TOTAL_TOKENS _CFG_MAX_TOTAL_TIME \
        _CFG_MAX_COST _CFG_MAX_TOTAL_COST \
        _CFG_MAX_TASK_ACTIONS _CFG_MAX_TASK_INPUT_TOKENS _CFG_MAX_TASK_OUTPUT_TOKENS \
        _CFG_MAX_TASK_TOKENS _CFG_MAX_TASK_TIME _CFG_MAX_TASK_COST
  unset LANEKEEP_TASK_ID \
        LANEKEEP_MAX_TASK_ACTIONS LANEKEEP_MAX_TASK_INPUT_TOKENS \
        LANEKEEP_MAX_TASK_OUTPUT_TOKENS LANEKEEP_MAX_TASK_TOKENS \
        LANEKEEP_MAX_TASK_TIME_SECONDS LANEKEEP_MAX_TASK_COST
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

# AC1: max_task_actions trips after N actions under the same TASK_ID
@test "task action cap fires when LANEKEEP_TASK_ID set and limit configured" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000, "max_task_actions": 3 } }
EOF

  export LANEKEEP_TASK_ID="task-A"
  for i in 1 2 3; do
    budget_eval "{}" "" "" "input" "session-1" "false"
    [ "$BUDGET_PASSED" = "true" ]
  done
  # 4th action under same task trips task cap
  budget_eval "{}" "" "" "input" "session-1" "false" || true
  [ "$BUDGET_PASSED" = "false" ]
  [[ "$BUDGET_REASON" == *"Task action budget"* ]]
}

# AC2: TASK_ID change resets task counters; new task gets full budget
@test "task counters reset when LANEKEEP_TASK_ID changes" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000, "max_task_actions": 2 } }
EOF

  export LANEKEEP_TASK_ID="task-A"
  budget_eval "{}" "" "" "input" "session-1" "false"
  budget_eval "{}" "" "" "input" "session-1" "false"
  [ "$BUDGET_PASSED" = "true" ]
  # 3rd would trip — but switch tasks first
  export LANEKEEP_TASK_ID="task-B"
  budget_eval "{}" "" "" "input" "session-1" "false"
  [ "$BUDGET_PASSED" = "true" ]
  # Verify state reflects task-B and reset counter
  [ "$(jq -r '.task_id' "$LANEKEEP_STATE_FILE")" = "task-B" ]
  [ "$(jq -r '.task_action_count' "$LANEKEEP_STATE_FILE")" = "1" ]
  budget_eval "{}" "" "" "input" "session-1" "false"
  [ "$BUDGET_PASSED" = "true" ]
  # 3rd under task-B trips
  budget_eval "{}" "" "" "input" "session-1" "false" || true
  [ "$BUDGET_PASSED" = "false" ]
  [[ "$BUDGET_REASON" == *"Task action budget"* ]]
}

# AC3: per-task scope is independent of per-session scope
@test "task scope does not affect session counters" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 10, "max_task_actions": 2 } }
EOF

  export LANEKEEP_TASK_ID="task-A"
  budget_eval "{}" "" "" "input" "session-1" "false"
  budget_eval "{}" "" "" "input" "session-1" "false"
  # Switch task — session counters keep climbing, task counters reset
  export LANEKEEP_TASK_ID="task-B"
  budget_eval "{}" "" "" "input" "session-1" "false"
  budget_eval "{}" "" "" "input" "session-1" "false"
  [ "$BUDGET_PASSED" = "true" ]
  # Session ran 4 actions, well under max_actions=10
  [ "$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")" = "4" ]
  [ "$(jq -r '.task_action_count' "$LANEKEEP_STATE_FILE")" = "2" ]
}

# AC4: no task limits configured and no TASK_ID set — zero behavioural change
@test "task scope dormant when LANEKEEP_TASK_ID unset" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000 } }
EOF

  # Run 5 actions, no task env set — task counters stay at 0, no caps fire
  for i in 1 2 3 4 5; do
    budget_eval "{}" "" "" "input" "session-1" "false"
    [ "$BUDGET_PASSED" = "true" ]
  done
  [ "$(jq -r '.task_id' "$LANEKEEP_STATE_FILE")" = "" ]
  [ "$(jq -r '.task_action_count' "$LANEKEEP_STATE_FILE")" = "0" ]
}

# AC5: env var override beats config value
@test "LANEKEEP_MAX_TASK_ACTIONS env override applies" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000, "max_task_actions": 100 } }
EOF

  export LANEKEEP_TASK_ID="task-A"
  export LANEKEEP_MAX_TASK_ACTIONS=2
  budget_eval "{}" "" "" "input" "session-1" "false"
  budget_eval "{}" "" "" "input" "session-1" "false"
  [ "$BUDGET_PASSED" = "true" ]
  # 3rd trips at env override of 2 (not config's 100)
  budget_eval "{}" "" "" "input" "session-1" "false" || true
  [ "$BUDGET_PASSED" = "false" ]
  [[ "$BUDGET_REASON" == *"Task action budget"* ]]
}

# AC6: task cap does NOT emit halted.json (per-invocation, not lifetime)
@test "task cap does not emit halt signal" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_actions": 1000, "max_task_actions": 1 } }
EOF

  export LANEKEEP_TASK_ID="task-A"
  budget_eval "{}" "" "" "input" "session-1" "false"
  budget_eval "{}" "" "" "input" "session-1" "false" || true
  [ "$BUDGET_PASSED" = "false" ]
  [ ! -f "$TEST_TMP/.lanekeep/halted.json" ]
}

# AC7: task input token cap (estimation mode — accumulates per task)
@test "task input token cap fires under estimation" {
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{ "budget": { "max_input_tokens": 100000, "max_task_input_tokens": 10 } }
EOF

  export LANEKEEP_TASK_ID="task-A"
  # Each "abcdefghij" string = ~3 tokens; do enough to exceed 10
  budget_eval "abcdefghij" "" "" "input" "session-1" "false"
  budget_eval "abcdefghij" "" "" "input" "session-1" "false"
  budget_eval "abcdefghij" "" "" "input" "session-1" "false"
  budget_eval "abcdefghij" "" "" "input" "session-1" "false" || true
  [ "$BUDGET_PASSED" = "false" ]
  [[ "$BUDGET_REASON" == *"Task input token budget"* ]]
}
