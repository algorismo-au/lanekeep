#!/usr/bin/env bats

LANEKEEP="$BATS_TEST_DIRNAME/../../bin/lanekeep"

# AC1: CLI Help
@test "lanekeep help exits 0 and contains 'governance sidecar'" {
  run "$LANEKEEP" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"governance sidecar"* ]]
}

@test "lanekeep --help exits 0" {
  run "$LANEKEEP" --help
  [ "$status" -eq 0 ]
}

@test "lanekeep with no args shows help" {
  run "$LANEKEEP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commands:"* ]]
}

# AC2: Unknown Command
@test "lanekeep foobar exits 1 with 'Unknown command' on stderr" {
  run "$LANEKEEP" foobar
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}

# AC3: lanekeep trace exits non-zero when no trace files exist
@test "lanekeep trace exits non-zero without trace dir" {
  local tmpdir
  tmpdir=$(mktemp -d)
  run env PROJECT_DIR="$tmpdir" "$LANEKEEP" trace
  [ "$status" -ne 0 ]
  rm -rf "$tmpdir"
}

@test "lanekeep init exits zero" {
  local tmpdir
  tmpdir=$(mktemp -d)
  run "$LANEKEEP" init "$tmpdir"
  [ "$status" -eq 0 ]
  rm -rf "$tmpdir"
}

# AC4: Default Config Valid JSON
@test "defaults/lanekeep.json is valid JSON with required keys" {
  run jq -e '.hard_blocks | type == "array"' "$BATS_TEST_DIRNAME/../../defaults/lanekeep.json"
  [ "$status" -eq 0 ]

  run jq -e '.budget | type == "object"' "$BATS_TEST_DIRNAME/../../defaults/lanekeep.json"
  [ "$status" -eq 0 ]

  run jq -e '.evaluators | type == "object"' "$BATS_TEST_DIRNAME/../../defaults/lanekeep.json"
  [ "$status" -eq 0 ]
}

@test "defaults/lanekeep.json has hard_blocks entries" {
  run jq -e '.hard_blocks | length > 0' "$BATS_TEST_DIRNAME/../../defaults/lanekeep.json"
  [ "$status" -eq 0 ]
}

@test "defaults/lanekeep.json has budget fields" {
  run jq -e '.budget.max_actions' "$BATS_TEST_DIRNAME/../../defaults/lanekeep.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "5000" ]]

  run jq -e '.budget.timeout_seconds' "$BATS_TEST_DIRNAME/../../defaults/lanekeep.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "432000" ]]
}

# AC5: All Fixtures Valid
@test "fixture lanekeep.json is valid JSON" {
  run jq -e '.' "$BATS_TEST_DIRNAME/../fixtures/lanekeep.json"
  [ "$status" -eq 0 ]
}

@test "fixture lanekeep-minimal.json is valid JSON" {
  run jq -e '.' "$BATS_TEST_DIRNAME/../fixtures/lanekeep-minimal.json"
  [ "$status" -eq 0 ]
}

@test "fixture taskspec-restrictive.json is valid JSON with allowed_tools" {
  run jq -e '.allowed_tools | length > 0' "$BATS_TEST_DIRNAME/../fixtures/taskspec-restrictive.json"
  [ "$status" -eq 0 ]
}

@test "fixture taskspec-open.json is valid JSON" {
  run jq -e '.' "$BATS_TEST_DIRNAME/../fixtures/taskspec-open.json"
  [ "$status" -eq 0 ]
}

@test "fixture taskspec-budget.json has max_actions" {
  run jq -e '.budget.max_actions' "$BATS_TEST_DIRNAME/../fixtures/taskspec-budget.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "10" ]]
}

@test "fixture hook-request-bash.json has tool_name Bash" {
  run jq -r '.tool_name' "$BATS_TEST_DIRNAME/../fixtures/hook-request-bash.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "Bash" ]]
}

@test "fixture hook-request-read.json has tool_name Read" {
  run jq -r '.tool_name' "$BATS_TEST_DIRNAME/../fixtures/hook-request-read.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "Read" ]]
}

@test "fixture hook-request-write-secret.json contains sk-" {
  run jq -r '.tool_input.content' "$BATS_TEST_DIRNAME/../fixtures/hook-request-write-secret.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sk-"* ]]
}

@test "fixture hook-request-rm.json has rm -rf command" {
  run jq -r '.tool_input.command' "$BATS_TEST_DIRNAME/../fixtures/hook-request-rm.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rm -rf"* ]]
}

@test "fixture ralph-events.jsonl has valid JSON lines" {
  while IFS= read -r line; do
    echo "$line" | jq -e '.' >/dev/null 2>&1
    [ $? -eq 0 ]
  done < "$BATS_TEST_DIRNAME/../fixtures/ralph-events.jsonl"
}

@test "fixture PRP-SAMPLE.md contains Goal section" {
  run grep -l "# Goal" "$BATS_TEST_DIRNAME/../fixtures/PRP-SAMPLE.md"
  [ "$status" -eq 0 ]
}

@test "fixture PRP-MINIMAL.md contains Goal section" {
  run grep -l "# Goal" "$BATS_TEST_DIRNAME/../fixtures/PRP-MINIMAL.md"
  [ "$status" -eq 0 ]
}
