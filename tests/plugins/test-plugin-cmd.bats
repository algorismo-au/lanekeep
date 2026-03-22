#!/usr/bin/env bats
# Tests for lanekeep plugin new/list/test commands

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"

  # Override PLUGIN_DIR to isolate tests
  export PLUGIN_DIR="$TEST_TMP/plugins.d"
  mkdir -p "$PLUGIN_DIR"

  # Patch lanekeep-plugin to use our test PLUGIN_DIR
  # We do this by exporting and running directly
}

teardown() {
  rm -rf "$TEST_TMP"
}

# Helper: run lanekeep-plugin with our test PLUGIN_DIR
_plugin() {
  LANEKEEP_DIR="$LANEKEEP_DIR" \
    "$LANEKEEP_DIR/bin/lanekeep-plugin" "$@"
}

# --- plugin new ---

@test "plugin new creates file at correct path" {
  _plugin new my-guard
  [ -f "$PLUGIN_DIR/my-guard.plugin.sh" ]
}

@test "plugin new file is executable" {
  _plugin new my-guard
  [ -x "$PLUGIN_DIR/my-guard.plugin.sh" ]
}

@test "plugin new file passes bash syntax check" {
  _plugin new my-guard
  bash -n "$PLUGIN_DIR/my-guard.plugin.sh"
}

@test "plugin new contains correct function name" {
  _plugin new my-guard
  grep -q 'my_guard_eval()' "$PLUGIN_DIR/my-guard.plugin.sh"
}

@test "plugin new contains correct global names" {
  _plugin new my-guard
  grep -q 'MY_GUARD_PASSED' "$PLUGIN_DIR/my-guard.plugin.sh"
  grep -q 'MY_GUARD_REASON' "$PLUGIN_DIR/my-guard.plugin.sh"
  grep -q 'MY_GUARD_DECISION' "$PLUGIN_DIR/my-guard.plugin.sh"
}

@test "plugin new contains registration line" {
  _plugin new my-guard
  grep -q 'LANEKEEP_PLUGIN_EVALS' "$PLUGIN_DIR/my-guard.plugin.sh"
  grep -q 'my_guard_eval' "$PLUGIN_DIR/my-guard.plugin.sh"
}

@test "plugin new rejects duplicate names" {
  _plugin new my-guard
  run _plugin new my-guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "plugin new rejects uppercase names" {
  run _plugin new MyGuard
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "plugin new rejects names with spaces" {
  run _plugin new "my guard"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "plugin new rejects names with special chars" {
  run _plugin new "my_guard"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "plugin new rejects names starting with number" {
  run _plugin new "1guard"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

# --- plugin list ---

@test "plugin list with no plugins shows 0" {
  output=$(_plugin list)
  [[ "$output" == *"0 plugin(s) found"* ]]
}

@test "plugin list after new shows created plugin" {
  _plugin new my-guard
  output=$(_plugin list)
  [[ "$output" == *"my-guard.plugin.sh"* ]]
  [[ "$output" == *"1 plugin(s) found"* ]]
}

@test "plugin list shows correct type for bash plugin" {
  _plugin new my-guard
  output=$(_plugin list)
  [[ "$output" == *"bash"* ]]
}

# --- plugin test ---

@test "plugin test with docker-safety detects docker rm -f" {
  cp "$LANEKEEP_DIR/plugins.d/examples/docker-safety.plugin.sh" "$PLUGIN_DIR/"
  output=$(_plugin test '{"command":"docker rm -f container1"}' --tool Bash)
  [[ "$output" == *"DENY"* ]]
}

@test "plugin test with safe command passes" {
  cp "$LANEKEEP_DIR/plugins.d/examples/docker-safety.plugin.sh" "$PLUGIN_DIR/"
  output=$(_plugin test '{"command":"ls -la"}' --tool Bash)
  [[ "$output" == *"PASS"* ]]
}

@test "plugin test with no plugins reports 0 tested" {
  output=$(_plugin test '{"command":"ls"}' --tool Bash)
  [[ "$output" == *"0 tested"* ]]
}
