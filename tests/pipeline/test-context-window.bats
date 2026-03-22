#!/usr/bin/env bats
# Tests for context window: model name extraction from transcript → state.json

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-ctx"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"

  # Copy transcript fixture (contains model: claude-opus-4-6)
  TRANSCRIPT_FIXTURE="$LANEKEEP_DIR/tests/fixtures/transcript-sample.jsonl"
  export TEST_TRANSCRIPT="$TEST_TMP/transcript.jsonl"
  cp "$TRANSCRIPT_FIXTURE" "$TEST_TRANSCRIPT"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

@test "Model name persisted to state.json from transcript" {
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-ctx\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  model=$(jq -r '.model' "$LANEKEEP_STATE_FILE")
  [ "$model" = "claude-opus-4-6" ]
}

@test "No model field when transcript unavailable" {
  echo '{"tool_name":"Read","tool_input":{"file_path":"x"},"session_id":"test-ctx"}' \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  model=$(jq -r '.model // "absent"' "$LANEKEEP_STATE_FILE")
  [ "$model" = "absent" ]
}

@test "Model updates when transcript changes" {
  # First call with opus transcript
  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x\"},\"session_id\":\"test-ctx\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  model1=$(jq -r '.model' "$LANEKEEP_STATE_FILE")
  [ "$model1" = "claude-opus-4-6" ]

  # Append entry with different model
  printf '{"type":"assistant","message":{"model":"claude-sonnet-4-5","role":"assistant","content":[{"type":"text","text":"Hi"}],"usage":{"input_tokens":50,"cache_creation_input_tokens":100,"cache_read_input_tokens":200,"output_tokens":30}},"sessionId":"test-session","uuid":"a9","timestamp":"2026-03-20T00:00:09.000Z"}\n' \
    >> "$TEST_TRANSCRIPT"

  echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"y\"},\"session_id\":\"test-ctx\",\"transcript_path\":\"$TEST_TRANSCRIPT\"}" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" > /dev/null

  model2=$(jq -r '.model' "$LANEKEEP_STATE_FILE")
  [ "$model2" = "claude-sonnet-4-5" ]
}
