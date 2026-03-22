#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/eval-schema.sh"
}

# AC1: Tool in Denylist
@test "schema_eval denies tool in denied_tools list" {
  export LANEKEEP_TASKSPEC_FILE="$BATS_TEST_DIRNAME/../fixtures/taskspec-restrictive.json"
  run schema_eval "Agent"
  [ "$status" -eq 1 ]
}

@test "schema_eval sets SCHEMA_PASSED=false and reason for denied tool" {
  export LANEKEEP_TASKSPEC_FILE="$BATS_TEST_DIRNAME/../fixtures/taskspec-restrictive.json"
  schema_eval "Agent" || true
  [ "$SCHEMA_PASSED" = "false" ]
  [[ "$SCHEMA_REASON" == *"denied_tools"* ]]
}

# AC2: Tool Not in Allowlist
@test "schema_eval denies tool not in allowed_tools" {
  export LANEKEEP_TASKSPEC_FILE="$BATS_TEST_DIRNAME/../fixtures/taskspec-restrictive.json"
  run schema_eval "Bash"
  [ "$status" -eq 1 ]
}

@test "schema_eval reason mentions 'not in allowed_tools' for unlisted tool" {
  export LANEKEEP_TASKSPEC_FILE="$BATS_TEST_DIRNAME/../fixtures/taskspec-restrictive.json"
  schema_eval "Bash" || true
  [[ "$SCHEMA_REASON" == *"not in allowed_tools"* ]]
}

# AC3: Tool in Allowlist
@test "schema_eval allows tool in allowed_tools" {
  export LANEKEEP_TASKSPEC_FILE="$BATS_TEST_DIRNAME/../fixtures/taskspec-restrictive.json"
  run schema_eval "Read"
  [ "$status" -eq 0 ]
}

# AC4: Empty Allowlist Allows All
@test "schema_eval allows any tool when allowed_tools is empty" {
  export LANEKEEP_TASKSPEC_FILE="$BATS_TEST_DIRNAME/../fixtures/taskspec-open.json"
  run schema_eval "Bash"
  [ "$status" -eq 0 ]
}

# AC5: No TaskSpec File
@test "schema_eval allows when taskspec file does not exist" {
  export LANEKEEP_TASKSPEC_FILE="/nonexistent/taskspec.json"
  run schema_eval "Bash"
  [ "$status" -eq 0 ]
}

@test "schema_eval allows when LANEKEEP_TASKSPEC_FILE is unset" {
  unset LANEKEEP_TASKSPEC_FILE
  run schema_eval "Bash"
  [ "$status" -eq 0 ]
}

# AC6: Denylist Before Allowlist (deny takes precedence)
@test "schema_eval denies tool that appears in both allowed and denied lists" {
  local tmpspec
  tmpspec=$(mktemp)
  cat > "$tmpspec" <<'JSON'
{
  "goal": "test",
  "allowed_tools": ["Bash"],
  "denied_tools": ["Bash"],
  "budget": {}
}
JSON
  export LANEKEEP_TASKSPEC_FILE="$tmpspec"
  run schema_eval "Bash"
  rm -f "$tmpspec"
  [ "$status" -eq 1 ]
}
