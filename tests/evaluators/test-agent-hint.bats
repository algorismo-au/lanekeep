#!/usr/bin/env bats
# Tests for agent_hint field on deny/ask responses across v1.1 evaluators
# Spec: specs/AGENT-OUTPUT-FORMAT.md
#
# Each evaluator that emits deny/ask MUST set its *_HINT global to a short,
# prefixed (DENIED:/APPROVAL NEEDED:/WARNING:), single-line, plain-text
# action directive. The handler routes this through agent_hint and the hook
# bridge forwards it to additionalContext.

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-agent-hint"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# Helper: assert hint is single-line, prefixed correctly, and within 200 chars
_assert_hint_well_formed() {
  local hint="$1"
  local expected_prefix="$2"
  [ -n "$hint" ] || { echo "agent_hint was empty"; return 1; }
  # Length cap (200 chars per spec constraint)
  [ "${#hint}" -le 200 ] || { echo "agent_hint exceeds 200 chars: $hint"; return 1; }
  # Single line — no embedded newlines
  case "$hint" in
    *$'\n'*) echo "agent_hint contains newline: $hint"; return 1 ;;
  esac
  # Correct prefix
  case "$hint" in
    "$expected_prefix"*) ;;
    *) echo "agent_hint missing '$expected_prefix' prefix: $hint"; return 1 ;;
  esac
}

# ---------------- HARDBLOCK (Tier 1) ----------------

@test "hardblock: agent_hint present and prefixed DENIED on hard-block" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  hint=$(printf '%s' "$output" | jq -r '.agent_hint // empty')
  [ "$decision" = "deny" ]
  _assert_hint_well_formed "$hint" "DENIED:"
}

# ---------------- RULES (Tier 2) ----------------

@test "rules: agent_hint present and prefixed DENIED on rule deny" {
  output=$(jq -c '.' "$LANEKEEP_DIR/tests/fixtures/hook-request-write-secret.json" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  hint=$(printf '%s' "$output" | jq -r '.agent_hint // empty')
  [ "$decision" = "deny" ]
  _assert_hint_well_formed "$hint" "DENIED:"
}

# ---------------- BUDGET (Tier 5) ----------------

@test "budget: agent_hint present and prefixed DENIED on action limit" {
  cp "$LANEKEEP_DIR/tests/fixtures/taskspec-budget.json" "$LANEKEEP_TASKSPEC_FILE"
  printf '{"action_count":10,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  hint=$(printf '%s' "$output" | jq -r '.agent_hint // empty')
  [ "$decision" = "deny" ]
  _assert_hint_well_formed "$hint" "DENIED:"
  [[ "$hint" == *"action limit"* ]] || [[ "$hint" == *"Action"* ]]
}

# ---------------- CONTEXT BUDGET (Tier 5.5) — unit-level ----------------

@test "context-budget: agent_hint DENIED at hard threshold" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-context-budget.sh"
  export _TRANSCRIPT_AVAILABLE=true
  export _TRANSCRIPT_INPUT_TOKENS=190000   # 95% of 200k
  unset _CFG_CONTEXT_WINDOW_SIZE _CFG_CONTEXT_SOFT_PERCENT _CFG_CONTEXT_HARD_PERCENT _CFG_CONTEXT_BUDGET_DECISION
  context_budget_eval "Bash" '{}' || true
  [ "$CONTEXT_BUDGET_DECISION" = "deny" ]
  _assert_hint_well_formed "$CONTEXT_BUDGET_HINT" "DENIED:"
  [[ "$CONTEXT_BUDGET_HINT" == *"%"* ]]
}

@test "context-budget: agent_hint APPROVAL NEEDED at soft threshold" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-context-budget.sh"
  export _TRANSCRIPT_AVAILABLE=true
  export _TRANSCRIPT_INPUT_TOKENS=160000   # 80% of 200k
  unset _CFG_CONTEXT_WINDOW_SIZE _CFG_CONTEXT_SOFT_PERCENT _CFG_CONTEXT_HARD_PERCENT _CFG_CONTEXT_BUDGET_DECISION
  context_budget_eval "Bash" '{}' || true
  [ "$CONTEXT_BUDGET_DECISION" = "ask" ]
  _assert_hint_well_formed "$CONTEXT_BUDGET_HINT" "APPROVAL NEEDED:"
}

@test "context-budget: agent_hint empty when below soft threshold" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-context-budget.sh"
  export _TRANSCRIPT_AVAILABLE=true
  export _TRANSCRIPT_INPUT_TOKENS=50000    # 25% of 200k
  unset _CFG_CONTEXT_WINDOW_SIZE _CFG_CONTEXT_SOFT_PERCENT _CFG_CONTEXT_HARD_PERCENT _CFG_CONTEXT_BUDGET_DECISION
  context_budget_eval "Bash" '{}'
  [ -z "$CONTEXT_BUDGET_HINT" ]
}

# ---------------- MULTI-SESSION (Tier 5.6) — unit-level ----------------

@test "multi-session: agent_hint WARNING on deny-rate anomaly" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-multi-session.sh"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/cumulative.json"
  jq -n '{total_sessions:5,total_actions:200,decisions:{allow:180,deny:20,ask:0},total_cost:0,top_denied_tools:{}}' \
    > "$LANEKEEP_CUMULATIVE_FILE"
  unset _CFG_MULTI_DENY_RATE _CFG_MULTI_TOOL_DENY _CFG_MULTI_COST_WARN _CFG_MULTI_MIN_SESSIONS _CFG_MAX_TOTAL_COST
  multi_session_eval "Bash" '{}' || true
  [ "$MULTI_SESSION_PASSED" = "false" ]
  _assert_hint_well_formed "$MULTI_SESSION_HINT" "WARNING:"
}

@test "multi-session: agent_hint WARNING on cost escalation" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-multi-session.sh"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/cumulative.json"
  jq -n '{total_sessions:5,total_actions:202,decisions:{allow:200,deny:2,ask:0},total_cost:85,top_denied_tools:{}}' \
    > "$LANEKEEP_CUMULATIVE_FILE"
  export _CFG_MULTI_DENY_RATE=100
  export _CFG_MULTI_TOOL_DENY=100000
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  export _CFG_MAX_TOTAL_COST=100
  multi_session_eval "Bash" '{}' || true
  [ "$MULTI_SESSION_PASSED" = "false" ]
  _assert_hint_well_formed "$MULTI_SESSION_HINT" "WARNING:"
}

@test "multi-session: agent_hint empty when within governance" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-multi-session.sh"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/cumulative.json"
  jq -n '{total_sessions:5,total_actions:205,decisions:{allow:200,deny:5,ask:0},total_cost:0,top_denied_tools:{}}' \
    > "$LANEKEEP_CUMULATIVE_FILE"
  unset _CFG_MULTI_DENY_RATE _CFG_MULTI_TOOL_DENY _CFG_MULTI_COST_WARN _CFG_MULTI_MIN_SESSIONS _CFG_MAX_TOTAL_COST
  multi_session_eval "Bash" '{}'
  [ -z "$MULTI_SESSION_HINT" ]
}

# ---------------- INPUT PII (Tier 4) — unit-level ----------------

@test "input-pii: agent_hint DENIED on PII deny" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-input-pii.sh"
  export _CFG_INPUT_PII_ON_DETECT="deny"
  # SSN-like pattern (3-2-4)
  export _CFG_INPUT_PII_PATTERNS=$'[0-9]{3}-[0-9]{2}-[0-9]{4}'
  export _CFG_INPUT_PII_COMPLIANCE="[]"
  export _CFG_INPUT_PII_HAS_TOOLS="false"
  input_pii_eval "Write" '{"content":"ssn: 123-45-6789"}' || true
  [ "$INPUT_PII_DECISION" = "deny" ]
  _assert_hint_well_formed "$INPUT_PII_HINT" "DENIED:"
}

@test "input-pii: agent_hint APPROVAL NEEDED on PII ask" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-input-pii.sh"
  export _CFG_INPUT_PII_ON_DETECT="ask"
  export _CFG_INPUT_PII_PATTERNS=$'[0-9]{3}-[0-9]{2}-[0-9]{4}'
  export _CFG_INPUT_PII_COMPLIANCE="[]"
  export _CFG_INPUT_PII_HAS_TOOLS="false"
  input_pii_eval "Write" '{"content":"ssn: 123-45-6789"}' || true
  [ "$INPUT_PII_DECISION" = "ask" ]
  _assert_hint_well_formed "$INPUT_PII_HINT" "APPROVAL NEEDED:"
}

@test "input-pii: agent_hint empty when no PII present" {
  # shellcheck disable=SC1091
  source "$LANEKEEP_DIR/lib/eval-input-pii.sh"
  export _CFG_INPUT_PII_ON_DETECT="ask"
  export _CFG_INPUT_PII_PATTERNS=$'[0-9]{3}-[0-9]{2}-[0-9]{4}'
  export _CFG_INPUT_PII_COMPLIANCE="[]"
  export _CFG_INPUT_PII_HAS_TOOLS="false"
  input_pii_eval "Write" '{"content":"hello world"}'
  [ -z "$INPUT_PII_HINT" ]
}

# ---------------- HANDLER (allow path) ----------------

@test "handler: agent_hint absent on allow response" {
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  has_hint=$(printf '%s' "$output" | jq -r 'has("agent_hint")')
  [ "$decision" = "allow" ]
  [ "$has_hint" = "false" ]
}

# ---------------- HOOK BRIDGE integration (jq merge check) ----------------

@test "hook-bridge: additionalContext present when agent_hint non-empty" {
  # Synthesize a handler-style response and feed it through the bridge logic
  # (we re-implement just the response shaping, matching hooks/evaluate.sh).
  resp='{"decision":"deny","reason":"[LaneKeep] DENIED: test","agent_hint":"DENIED: test hint."}'
  reason=$(printf '%s' "$resp" | jq -r '.reason')
  hint=$(printf '%s' "$resp" | jq -r '.agent_hint // empty')
  out=$(jq -n -c --arg reason "$reason" --arg hint "$hint" '{
    hookSpecificOutput: (
      {hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$reason}
      + (if $hint != "" then {additionalContext:$hint} else {} end)
    )
  }')
  ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')
  [ "$ctx" = "DENIED: test hint." ]
}

@test "hook-bridge: additionalContext omitted when agent_hint empty" {
  resp='{"decision":"deny","reason":"[LaneKeep] DENIED: test"}'
  reason=$(printf '%s' "$resp" | jq -r '.reason')
  hint=$(printf '%s' "$resp" | jq -r '.agent_hint // empty')
  out=$(jq -n -c --arg reason "$reason" --arg hint "$hint" '{
    hookSpecificOutput: (
      {hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$reason}
      + (if $hint != "" then {additionalContext:$hint} else {} end)
    )
  }')
  has_ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput | has("additionalContext")')
  [ "$has_ctx" = "false" ]
}
