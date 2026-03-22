#!/usr/bin/env bats
# Tests for config loader

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  PROJECT_DIR="$TEST_TMP/project"
  mkdir -p "$PROJECT_DIR"

  source "$LANEKEEP_DIR/lib/config.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

@test "load_config: creates .lanekeep directories" {
  load_config "$PROJECT_DIR"
  [ -d "$PROJECT_DIR/.lanekeep" ]
  [ -d "$PROJECT_DIR/.lanekeep/traces" ]
}

@test "load_config: uses project lanekeep.json when present" {
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$PROJECT_DIR/lanekeep.json"
  load_config "$PROJECT_DIR"
  [ "$LANEKEEP_CONFIG_FILE" = "$PROJECT_DIR/lanekeep.json" ]
}

@test "load_config: falls back to defaults when no project lanekeep.json" {
  load_config "$PROJECT_DIR"
  [ "$LANEKEEP_CONFIG_FILE" = "$PROJECT_DIR/.lanekeep/resolved-config.json" ]
  # Verify the copy has the same rules as defaults
  local defaults_count resolved_count
  defaults_count=$(jq '.rules | length' "$LANEKEEP_DIR/defaults/lanekeep.json")
  resolved_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$resolved_count" -ge "$defaults_count" ]
}

@test "load_config: generates session ID" {
  load_config "$PROJECT_DIR"
  [ -n "$LANEKEEP_SESSION_ID" ]
  [[ "$LANEKEEP_SESSION_ID" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]]
}

@test "load_config: initializes state file" {
  load_config "$PROJECT_DIR"
  [ -f "$LANEKEEP_STATE_FILE" ]
  action_count=$(jq -r '.action_count' "$LANEKEEP_STATE_FILE")
  [ "$action_count" -eq 0 ]
  token_count=$(jq -r '.token_count' "$LANEKEEP_STATE_FILE")
  [ "$token_count" -eq 0 ]
}

@test "load_config: sets trace file path" {
  load_config "$PROJECT_DIR"
  [[ "$LANEKEEP_TRACE_FILE" == *"$LANEKEEP_SESSION_ID"* ]]
  [[ "$LANEKEEP_TRACE_FILE" == *".jsonl" ]]
}

@test "load_config: parses spec file when provided" {
  load_config "$PROJECT_DIR" "$LANEKEEP_DIR/tests/fixtures/PRP-SAMPLE.md"
  [ -f "$LANEKEEP_TASKSPEC_FILE" ]
  goal=$(jq -r '.goal' "$LANEKEEP_TASKSPEC_FILE")
  [[ "$goal" == *"network"* ]] || [[ "$goal" == *"LaneKeep"* ]]
}

@test "load_config: works without spec file" {
  load_config "$PROJECT_DIR"
  # Should not fail, taskspec path set but may not exist
  [ -n "$LANEKEEP_TASKSPEC_FILE" ]
}

@test "load_config: exports all required env vars" {
  load_config "$PROJECT_DIR"
  [ -n "$LANEKEEP_DIR" ]
  [ -n "$LANEKEEP_CONFIG_FILE" ]
  [ -n "$LANEKEEP_SESSION_ID" ]
  [ -n "$LANEKEEP_TASKSPEC_FILE" ]
  [ -n "$LANEKEEP_STATE_FILE" ]
  [ -n "$LANEKEEP_TRACE_FILE" ]
}

@test "load_config: state file has start_epoch" {
  load_config "$PROJECT_DIR"
  epoch=$(jq -r '.start_epoch' "$LANEKEEP_STATE_FILE")
  [ "$epoch" -gt 0 ]
}
