#!/usr/bin/env bats
# Tests for cumulative risk scoring (feat-cumulative-risk-scoring).
# End-to-end via the handler: seeds state.json with prior warn/ask counts,
# fires a request that would otherwise pass, and asserts the response
# escalates.

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP"

  mkdir -p "$PROJECT_DIR/.lanekeep/traces"
  export LANEKEEP_STATE_FILE="$PROJECT_DIR/.lanekeep/state.json"
  export LANEKEEP_TRACE_FILE="$PROJECT_DIR/.lanekeep/traces/test-risk.jsonl"
  export LANEKEEP_SESSION_ID="test-risk-$$"
  export LANEKEEP_CUMULATIVE_FILE="$PROJECT_DIR/.lanekeep/cumulative.json"
  export LANEKEEP_TASKSPEC_FILE=""
  export LANEKEEP_LICENSE_TIER="community"

  # Minimal config that keeps other evaluators quiet + enables risk_score.
  cat > "$PROJECT_DIR/lanekeep.json" <<'JSON'
{
  "hard_blocks": [],
  "hard_blocks_regex": [],
  "rules": [],
  "policies": {},
  "budget": {},
  "evaluators": {
    "hidden_text": {"enabled": false},
    "input_pii": {"enabled": false},
    "semantic": {"enabled": false},
    "workflow_injection": {"enabled": false},
    "repo_injection": {"enabled": false},
    "session_write_exec": {"enabled": false},
    "context_budget": {"enabled": false},
    "multi_session": {"enabled": false},
    "scope_containment": {"enabled": false},
    "risk_score": {
      "enabled": true,
      "warn_threshold": 3,
      "ask_threshold": 5
    }
  }
}
JSON
  export LANEKEEP_CONFIG_FILE="$PROJECT_DIR/lanekeep.json"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

_seed_state() {
  # $1=warn_count $2=ask_count
  local w="${1:-0}" a="${2:-0}"
  jq -n --argjson w "$w" --argjson a "$a" \
    '{action_count:0, token_count:0, input_tokens:0, output_tokens:0,
      cache_creation_input_tokens:0, cache_read_input_tokens:0,
      total_events:0, warn_count:$w, ask_count:$a,
      start_epoch:0, session_id:"test-cc", lanekeep_session_id:"test-lk"}' \
    > "$LANEKEEP_STATE_FILE"
}

_invoke() {
  # Simulate a Read that would otherwise pass through the pipeline.
  local input
  input=$(jq -n '{tool_name:"Read", tool_input:{file_path:"README.md"},
                  session_id:"test-cc"}')
  printf '%s' "$input" | "$LANEKEEP_DIR/bin/lanekeep-handler"
}

# ── Below thresholds → no escalation ──

@test "risk below warn threshold → allow unchanged" {
  _seed_state 0 0
  run _invoke
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"allow"'* ]]
}

@test "risk 2 warns (< warn threshold 3) → still allow" {
  _seed_state 2 0
  run _invoke
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"allow"'* ]]
}

# ── Warn threshold met → allow → warn ──

@test "risk at warn threshold (3 warns) → escalates to warn" {
  _seed_state 3 0
  run _invoke
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"warn"'* ]]
  [[ "$output" == *"CumulativeRiskScoring"* ]]
}

@test "risk crosses warn threshold via warn+ask mix → warn" {
  _seed_state 2 1
  run _invoke
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"warn"'* ]]
}

# ── Ask threshold met → escalates to ask ──

@test "risk at ask threshold (5 total) → escalates to ask" {
  _seed_state 3 2
  run _invoke
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"ask"'* ]]
  [[ "$output" == *"CumulativeRiskScoring"* ]]
}

@test "risk at ask threshold takes precedence over warn escalation" {
  _seed_state 5 0
  run _invoke
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"ask"'* ]]
}

# ── Opt-in semantics ──

@test "risk_score disabled → no escalation regardless of counts" {
  jq '.evaluators.risk_score.enabled = false' "$LANEKEEP_CONFIG_FILE" \
    > "$LANEKEEP_CONFIG_FILE.tmp" && mv "$LANEKEEP_CONFIG_FILE.tmp" "$LANEKEEP_CONFIG_FILE"
  _seed_state 100 100
  run _invoke
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"allow"'* ]]
}

# ── Counter increment (state.json write-back) ──

@test "warn decision increments warn_count in state.json" {
  # Seed at warn threshold so this request escalates to warn.
  _seed_state 3 0
  _invoke >/dev/null
  # After the handler runs: eval-budget wrote state.json with warn_count=3,
  # then the post-decision jq increment bumped it to 4.
  new_warn=$(jq '.warn_count' "$LANEKEEP_STATE_FILE")
  [ "$new_warn" = "4" ]
}

@test "ask decision increments ask_count in state.json" {
  _seed_state 3 2
  _invoke >/dev/null
  new_ask=$(jq '.ask_count' "$LANEKEEP_STATE_FILE")
  [ "$new_ask" = "3" ]
}

@test "allow decision does not increment either counter" {
  _seed_state 0 0
  _invoke >/dev/null
  [ "$(jq '.warn_count' "$LANEKEEP_STATE_FILE")" = "0" ]
  [ "$(jq '.ask_count' "$LANEKEEP_STATE_FILE")" = "0" ]
}

# ── State-file resilience ──

@test "missing state.json → no crash, no escalation" {
  # No _seed_state call — file doesn't exist. Handler must not crash.
  rm -f "$LANEKEEP_STATE_FILE"
  run _invoke
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"allow"'* ]]
}

@test "missing warn_count/ask_count fields default to 0" {
  jq -n '{action_count:0, session_id:"x"}' > "$LANEKEEP_STATE_FILE"
  run _invoke
  [ "$status" -eq 0 ]
  # Should not escalate — counts default to 0.
  [[ "$output" == *'"decision":"allow"'* ]]
}
