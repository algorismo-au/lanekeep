#!/usr/bin/env bats
# Tests for the headless escalation sink
# Spec: specs/HEADLESS-ESCALATION-SINK.md (buildinglanekeep meta-repo)

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_TASKSPEC_FILE=""
  export LANEKEEP_STATE_FILE="$TEST_TMP/.lanekeep/state.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="hes-test-session"
  export LANEKEEP_ESCALATION_DIR="$TEST_TMP/.lanekeep/escalations"
  mkdir -p "$TEST_TMP/.lanekeep/traces" "$TEST_TMP/.lanekeep"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  source "$LANEKEEP_DIR/lib/headless.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
  unset LANEKEEP_HEADLESS LANEKEEP_TASK_ID LANEKEEP_ESCALATION_DIR LANEKEEP_LOOP_ID
  return 0
}

# Run the handler with a request that triggers an `ask` decision.
# Uses sys-026 (curl --insecure) — shipped default rule with decision: "ask".
_ask_request() {
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","tool_name":"Bash","tool_input":{"command":"curl --insecure https://example.com"}}' \
    "$LANEKEEP_SESSION_ID"
}

# --- Unit tests: lib/headless.sh ---

@test "is_active false when LANEKEEP_HEADLESS unset" {
  unset LANEKEEP_HEADLESS
  run headless::is_active
  [ "$status" -ne 0 ]
}

@test "is_active true for LANEKEEP_HEADLESS=1" {
  LANEKEEP_HEADLESS=1 run headless::is_active
  [ "$status" -eq 0 ]
}

@test "is_active accepts true/yes (case-insensitive)" {
  LANEKEEP_HEADLESS=true run headless::is_active
  [ "$status" -eq 0 ]
  LANEKEEP_HEADLESS=YES run headless::is_active
  [ "$status" -eq 0 ]
  LANEKEEP_HEADLESS=True run headless::is_active
  [ "$status" -eq 0 ]
}

@test "is_active rejects 0, empty, garbage" {
  LANEKEEP_HEADLESS=0 run headless::is_active
  [ "$status" -ne 0 ]
  LANEKEEP_HEADLESS="" run headless::is_active
  [ "$status" -ne 0 ]
  LANEKEEP_HEADLESS=maybe run headless::is_active
  [ "$status" -ne 0 ]
}

@test "escalation_id prefers LANEKEEP_TASK_ID over session id" {
  LANEKEEP_TASK_ID=T-42 run headless::escalation_id "sess-99"
  [ "$status" -eq 0 ]
  [ "$output" = "T-42" ]
}

@test "escalation_id falls back to session id when no task id" {
  unset LANEKEEP_TASK_ID
  run headless::escalation_id "sess-99"
  [ "$output" = "sess-99" ]
}

@test "escalation_id falls back to unattached-<epoch> with neither" {
  unset LANEKEEP_TASK_ID
  run headless::escalation_id ""
  [[ "$output" =~ ^unattached-[0-9]+$ ]]
}

@test "escalation_dir honours LANEKEEP_ESCALATION_DIR override" {
  LANEKEEP_ESCALATION_DIR=/tmp/custom-esc run headless::escalation_dir
  [ "$output" = "/tmp/custom-esc" ]
}

# --- Integration tests: handler interception ---

@test "ask passes through unchanged when headless not set" {
  unset LANEKEEP_HEADLESS
  output=$(_ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
  [ ! -d "$LANEKEEP_ESCALATION_DIR" ]
}

@test "ask rewritten to deny when LANEKEEP_HEADLESS=1" {
  export LANEKEEP_HEADLESS=1
  export LANEKEEP_TASK_ID="T-headless-1"
  output=$(_ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [ "$decision" = "deny" ]
  [[ "$reason" == *"escalated (headless)"* ]]
}

@test "bundle file written with task id name" {
  export LANEKEEP_HEADLESS=1
  export LANEKEEP_TASK_ID="T-headless-2"
  _ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null
  [ -f "$LANEKEEP_ESCALATION_DIR/T-headless-2.json" ]
}

@test "bundle file uses session id when task id unset" {
  export LANEKEEP_HEADLESS=1
  unset LANEKEEP_TASK_ID
  _ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null
  [ -f "$LANEKEEP_ESCALATION_DIR/$LANEKEEP_SESSION_ID.json" ]
}

@test "bundle schema has required fields" {
  export LANEKEEP_HEADLESS=1
  export LANEKEEP_TASK_ID="T-schema"
  _ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null
  bundle="$LANEKEEP_ESCALATION_DIR/T-schema.json"
  [ -f "$bundle" ]
  schema=$(jq -r '.schema_version' "$bundle")
  [ "$schema" = "1.0" ]
  [ "$(jq -r '.task_id' "$bundle")" = "T-schema" ]
  [ "$(jq -r '.original_decision' "$bundle")" = "ask" ]
  [ "$(jq -r '.rewritten_to' "$bundle")" = "deny" ]
  [ "$(jq -r '.tool_name' "$bundle")" = "Bash" ]
  [ "$(jq -r '.escalation_count' "$bundle")" = "1" ]
  [ "$(jq -r '.tier_results | type' "$bundle")" = "array" ]
  [ "$(jq -r '.trace_tail | type' "$bundle")" = "array" ]
  [ "$(jq -r '.env_snapshot.LANEKEEP_HEADLESS' "$bundle")" = "1" ]
  [ "$(jq -r '.env_snapshot.LANEKEEP_TASK_ID' "$bundle")" = "T-schema" ]
}

@test "second escalation for same task overwrites with incremented count" {
  export LANEKEEP_HEADLESS=1
  export LANEKEEP_TASK_ID="T-multi"
  _ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null
  _ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null
  bundle="$LANEKEEP_ESCALATION_DIR/T-multi.json"
  count=$(jq -r '.escalation_count' "$bundle")
  [ "$count" = "2" ]
}

@test "trace entry has original_decision=ask and decision=deny" {
  export LANEKEEP_HEADLESS=1
  export LANEKEEP_TASK_ID="T-trace"
  _ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null
  [ -f "$LANEKEEP_TRACE_FILE" ]
  last=$(tail -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$last" | jq -r '.decision')" = "deny" ]
  [ "$(printf '%s' "$last" | jq -r '.original_decision')" = "ask" ]
}

@test "allow decisions never write bundle" {
  export LANEKEEP_HEADLESS=1
  export LANEKEEP_TASK_ID="T-allow"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null
  [ ! -d "$LANEKEEP_ESCALATION_DIR" ] || [ -z "$(ls -A "$LANEKEEP_ESCALATION_DIR" 2>/dev/null)" ]
}

@test "warn decisions pass through unchanged in headless mode" {
  export LANEKEEP_HEADLESS=1
  export LANEKEEP_TASK_ID="T-warn"
  # Read of a non-existent file — not blocked, but not ask either; covers the
  # non-ask branch through the same env.
  output=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" != "deny" ]
  [ ! -f "$LANEKEEP_ESCALATION_DIR/T-warn.json" ]
}

@test "best-effort: read-only escalation dir does not break the deny response" {
  export LANEKEEP_HEADLESS=1
  export LANEKEEP_TASK_ID="T-readonly"
  mkdir -p "$LANEKEEP_ESCALATION_DIR"
  chmod 0555 "$LANEKEEP_ESCALATION_DIR"
  output=$(_ask_request | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  chmod 0700 "$LANEKEEP_ESCALATION_DIR"
  [ "$decision" = "deny" ]
}
