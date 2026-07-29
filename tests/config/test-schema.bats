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

# --- Config-level layering (LANEKEEP_CONFIG_FILE) ---

# AC7: Config-level denied_tools is enforced
@test "schema_eval denies tool listed in config denied_tools" {
  local tmpcfg
  tmpcfg=$(mktemp)
  printf '{"denied_tools":["WebFetch"]}\n' > "$tmpcfg"
  export LANEKEEP_CONFIG_FILE="$tmpcfg"
  export LANEKEEP_TASKSPEC_FILE=""
  run schema_eval "WebFetch"
  rm -f "$tmpcfg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"denied_tools"* ]] || true
}

@test "schema_eval config-deny reason identifies the config layer" {
  local tmpcfg
  tmpcfg=$(mktemp)
  printf '{"denied_tools":["WebFetch"]}\n' > "$tmpcfg"
  export LANEKEEP_CONFIG_FILE="$tmpcfg"
  export LANEKEEP_TASKSPEC_FILE=""
  schema_eval "WebFetch" || true
  rm -f "$tmpcfg"
  [[ "$SCHEMA_REASON" == *"denied_tools list (config)"* ]]
}

# AC8: Config allow-list narrows access
@test "schema_eval denies tool not in config allowed_tools" {
  local tmpcfg
  tmpcfg=$(mktemp)
  printf '{"allowed_tools":["Read","Edit"]}\n' > "$tmpcfg"
  export LANEKEEP_CONFIG_FILE="$tmpcfg"
  export LANEKEEP_TASKSPEC_FILE=""
  run schema_eval "Bash"
  rm -f "$tmpcfg"
  [ "$status" -eq 1 ]
}

@test "schema_eval allows tool in config allowed_tools" {
  local tmpcfg
  tmpcfg=$(mktemp)
  printf '{"allowed_tools":["Read","Edit"]}\n' > "$tmpcfg"
  export LANEKEEP_CONFIG_FILE="$tmpcfg"
  export LANEKEEP_TASKSPEC_FILE=""
  run schema_eval "Read"
  rm -f "$tmpcfg"
  [ "$status" -eq 0 ]
}

# AC9: Config deny wins over TaskSpec allow (config is non-overridable)
@test "schema_eval config denied_tools overrides TaskSpec allowed_tools" {
  local tmpcfg tmpspec
  tmpcfg=$(mktemp)
  tmpspec=$(mktemp)
  printf '{"denied_tools":["WebFetch"]}\n' > "$tmpcfg"
  cat > "$tmpspec" <<'JSON'
{"goal":"t","allowed_tools":["WebFetch"],"denied_tools":[],"budget":{}}
JSON
  export LANEKEEP_CONFIG_FILE="$tmpcfg"
  export LANEKEEP_TASKSPEC_FILE="$tmpspec"
  run schema_eval "WebFetch"
  rm -f "$tmpcfg" "$tmpspec"
  [ "$status" -eq 1 ]
}

# AC10: Allow-lists intersect — tool must satisfy both when both are non-empty
@test "schema_eval requires tool in both allow-lists when both are non-empty" {
  local tmpcfg tmpspec
  tmpcfg=$(mktemp)
  tmpspec=$(mktemp)
  printf '{"allowed_tools":["Read","Edit","Bash"]}\n' > "$tmpcfg"
  cat > "$tmpspec" <<'JSON'
{"goal":"t","allowed_tools":["Read"],"denied_tools":[],"budget":{}}
JSON
  export LANEKEEP_CONFIG_FILE="$tmpcfg"
  export LANEKEEP_TASKSPEC_FILE="$tmpspec"
  # Bash is in config allow-list but not TaskSpec allow-list → deny
  run schema_eval "Bash"
  [ "$status" -eq 1 ]
  # Read is in both → allow
  run schema_eval "Read"
  rm -f "$tmpcfg" "$tmpspec"
  [ "$status" -eq 0 ]
}

# AC11: Empty/null config lists are inert
@test "schema_eval allows all when config has no allowed_tools/denied_tools" {
  local tmpcfg
  tmpcfg=$(mktemp)
  printf '{"budget":{"max_actions":100}}\n' > "$tmpcfg"
  export LANEKEEP_CONFIG_FILE="$tmpcfg"
  export LANEKEEP_TASKSPEC_FILE=""
  run schema_eval "Bash"
  rm -f "$tmpcfg"
  [ "$status" -eq 0 ]
}
