#!/usr/bin/env bats
# Tests for PRP-to-TaskSpec parser

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

@test "parse-spec: extracts goal from sample PRP" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-SAMPLE.md")
  goal=$(echo "$result" | jq -r '.goal')
  [[ "$goal" == *"network"* ]]
  [[ "$goal" == *"plugin"* ]]
}

@test "parse-spec: extracts denied tools from anti-patterns" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-SAMPLE.md")
  denied=$(echo "$result" | jq -r '.denied_tools[]')
  [[ "$denied" == *"Agent"* ]]
}

@test "parse-spec: extracts max_actions from budget" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-SAMPLE.md")
  max=$(echo "$result" | jq '.budget.max_actions')
  [ "$max" -eq 50 ]
}

@test "parse-spec: converts timeout minutes to seconds" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-SAMPLE.md")
  timeout=$(echo "$result" | jq '.budget.timeout_seconds')
  [ "$timeout" -eq 1800 ]
}

@test "parse-spec: minimal PRP has goal only" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-MINIMAL.md")
  goal=$(echo "$result" | jq -r '.goal')
  [[ "$goal" == *"typo"* ]]
  denied=$(echo "$result" | jq '.denied_tools | length')
  [ "$denied" -eq 0 ]
  max=$(echo "$result" | jq '.budget.max_actions')
  [ "$max" = "null" ]
}

@test "parse-spec: output is valid JSON" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-SAMPLE.md")
  echo "$result" | jq -e '.' >/dev/null
}

@test "parse-spec: output has all required fields" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-SAMPLE.md")
  echo "$result" | jq -e '.goal' >/dev/null
  echo "$result" | jq -e '.allowed_tools' >/dev/null
  echo "$result" | jq -e '.denied_tools' >/dev/null
  echo "$result" | jq -e '.budget' >/dev/null
}

@test "parse-spec: allowed_tools defaults to empty array when no section" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-MINIMAL.md")
  len=$(echo "$result" | jq '.allowed_tools | length')
  [ "$len" -eq 0 ]
}

@test "parse-spec: extracts allowed_tools from Implementation Blueprint" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$LANEKEEP_DIR/tests/fixtures/PRP-SAMPLE.md")
  allowed=$(echo "$result" | jq -r '.allowed_tools[]')
  [[ "$allowed" == *"Write"* ]]
  [[ "$allowed" == *"Edit"* ]]
  [[ "$allowed" == *"Bash"* ]]
}

@test "parse-spec: extracts allowed_tools from Allowed Tools section" {
  cat > "$TEST_TMP/allowed.md" <<'EOF'
# Goal

Test allowed tools extraction

## Allowed Tools

- Read
- Grep
- Glob

## Budget

- Maximum 20 actions
EOF
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$TEST_TMP/allowed.md")
  len=$(echo "$result" | jq '.allowed_tools | length')
  [ "$len" -eq 3 ]
  allowed=$(echo "$result" | jq -r '.allowed_tools[]')
  [[ "$allowed" == *"Read"* ]]
  [[ "$allowed" == *"Grep"* ]]
  [[ "$allowed" == *"Glob"* ]]
}

@test "parse-spec: fails on missing file" {
  run "$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$TEST_TMP/nonexistent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "parse-spec: fails with no arguments" {
  run "$LANEKEEP_DIR/bin/lanekeep-parse-spec"
  [ "$status" -ne 0 ]
}

@test "parse-spec: handles PRP with no sections" {
  echo "Just a plain text file with no markdown sections." > "$TEST_TMP/plain.md"
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$TEST_TMP/plain.md")
  # Should still produce valid JSON with empty goal
  echo "$result" | jq -e '.' >/dev/null
  max=$(echo "$result" | jq '.budget.max_actions')
  [ "$max" = "null" ]
}

@test "parse-spec: handles PRP with goal as heading text" {
  cat > "$TEST_TMP/heading-goal.md" <<'EOF'
# Build a REST API for todos

## Budget

- Maximum 100 actions
EOF
  result=$("$LANEKEEP_DIR/bin/lanekeep-parse-spec" "$TEST_TMP/heading-goal.md")
  goal=$(echo "$result" | jq -r '.goal')
  [[ "$goal" == *"REST API"* ]]
  max=$(echo "$result" | jq '.budget.max_actions')
  [ "$max" -eq 100 ]
}
