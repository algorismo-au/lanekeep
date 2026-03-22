#!/usr/bin/env bats
# Tests for real token tracking from Claude Code transcript JSONL

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-transcript"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"

  # Copy transcript fixture
  TRANSCRIPT_FIXTURE="$LANEKEEP_DIR/tests/fixtures/transcript-sample.jsonl"
  export TEST_TRANSCRIPT="$TEST_TMP/transcript.jsonl"
  cp "$TRANSCRIPT_FIXTURE" "$TEST_TRANSCRIPT"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

@test "Transcript tokens replace estimation for input_tokens" {
  # Last assistant entry: input=15 + cache_creation=800 + cache_read=2000 = 2815
  output=$(echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  input_tokens=$(jq -r '.input_tokens' "$LANEKEEP_STATE_FILE")
  [ "$input_tokens" -eq 2815 ]
}

@test "token_source is transcript when transcript available" {
  output=$(echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  token_source=$(jq -r '.token_source' "$LANEKEEP_STATE_FILE")
  [ "$token_source" = "transcript" ]
}

@test "Fallback to estimate when transcript_path missing" {
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"test-transcript"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  token_source=$(jq -r '.token_source' "$LANEKEEP_STATE_FILE")
  [ "$token_source" = "estimate" ]

  # Estimated tokens should be > 0 (from tool_input JSON)
  input_tokens=$(jq -r '.input_tokens' "$LANEKEEP_STATE_FILE")
  [ "$input_tokens" -gt 0 ]
}

@test "Fallback when transcript file does not exist" {
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"test-transcript","transcript_path":"/nonexistent/path.jsonl"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]

  token_source=$(jq -r '.token_source' "$LANEKEEP_STATE_FILE")
  [ "$token_source" = "estimate" ]
}

@test "Snapshot semantics: input_tokens reflects latest context not cumulative" {
  # First call with transcript
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  input_after_first=$(jq -r '.input_tokens' "$LANEKEEP_STATE_FILE")
  [ "$input_after_first" -eq 2815 ]

  # Second call with same transcript — input_tokens should still be 2815 (snapshot), not doubled
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"y\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  input_after_second=$(jq -r '.input_tokens' "$LANEKEEP_STATE_FILE")
  [ "$input_after_second" -eq 2815 ]
}

@test "Budget denial with transcript tokens exceeding limit" {
  # Set max_input_tokens to 2000 (transcript will report 2815)
  jq '.budget.max_input_tokens = 2000' "$LANEKEEP_CONFIG_FILE" > "$TEST_TMP/cfg.tmp" \
    && mv "$TEST_TMP/cfg.tmp" "$LANEKEEP_CONFIG_FILE"

  output=$(echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler")

  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]

  reason=$(printf '%s' "$output" | jq -r '.reason')
  [[ "$reason" == *"Input token budget exceeded"* ]]
  [[ "$reason" == *"2815"* ]]
}

@test "Output tokens still use estimation (unaffected by transcript)" {
  # First PreToolUse call with transcript
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  output_before=$(jq -r '.output_tokens' "$LANEKEEP_STATE_FILE")
  [ "$output_before" -eq 0 ]

  # PostToolUse call — output tokens come from estimation, not transcript
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"hook_event_name\":\"PostToolUse\",\"tool_response\":{\"output\":\"some result text here\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  output_after=$(jq -r '.output_tokens' "$LANEKEEP_STATE_FILE")
  [ "$output_after" -gt 0 ]
}

@test "Transcript with growing context updates input_tokens snapshot" {
  # Start with initial transcript
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  input_before=$(jq -r '.input_tokens' "$LANEKEEP_STATE_FILE")
  [ "$input_before" -eq 2815 ]

  # Append a new assistant entry with larger context
  printf '{"type":"assistant","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"More"}],"usage":{"input_tokens":100,"cache_creation_input_tokens":1000,"cache_read_input_tokens":5000,"output_tokens":200}},"sessionId":"test-session","uuid":"a3","timestamp":"2026-03-20T00:00:04.000Z"}\n' \
    >> "$TEST_TRANSCRIPT"

  # Second call should pick up new context size: 100+1000+5000 = 6100
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"y\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  input_after=$(jq -r '.input_tokens' "$LANEKEEP_STATE_FILE")
  [ "$input_after" -eq 6100 ]
}

@test "PostToolUse preserves token_source and model from preceding PreToolUse" {
  # PreToolUse: reads transcript, sets token_source=transcript and model
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  token_source_pre=$(jq -r '.token_source' "$LANEKEEP_STATE_FILE")
  model_pre=$(jq -r '.model' "$LANEKEEP_STATE_FILE")
  [ "$token_source_pre" = "transcript" ]
  [ "$model_pre" = "claude-opus-4-6" ]

  # PostToolUse: skips transcript read — should preserve token_source and model
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"hook_event_name\":\"PostToolUse\",\"tool_response\":{\"output\":\"result\"},\"session_id\":\"test-transcript\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  token_source_post=$(jq -r '.token_source' "$LANEKEEP_STATE_FILE")
  model_post=$(jq -r '.model' "$LANEKEEP_STATE_FILE")
  [ "$token_source_post" = "transcript" ]
  [ "$model_post" = "claude-opus-4-6" ]
}
