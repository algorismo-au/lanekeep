#!/usr/bin/env bats
# Tests for polyglot (non-bash) plugin support

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-polyglot"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  # Create isolated plugin dir using real plugins.d as base
  # (handler uses $LANEKEEP_DIR/plugins.d hardcoded)
  REAL_PLUGIN_DIR="$LANEKEEP_DIR/plugins.d"
  BACKUP_DIR="$TEST_TMP/plugins-backup"
  mkdir -p "$BACKUP_DIR"

  # Save any existing active plugins
  for f in "$REAL_PLUGIN_DIR"/*.plugin.sh "$REAL_PLUGIN_DIR"/*.plugin.py \
           "$REAL_PLUGIN_DIR"/*.plugin.js "$REAL_PLUGIN_DIR"/*.plugin; do
    [ -f "$f" ] && cp "$f" "$BACKUP_DIR/" || true
  done

  # Clean real plugin dir of active plugins for test isolation
  rm -f "$REAL_PLUGIN_DIR"/*.plugin.sh "$REAL_PLUGIN_DIR"/*.plugin.py \
        "$REAL_PLUGIN_DIR"/*.plugin.js "$REAL_PLUGIN_DIR"/*.plugin
}

teardown() {
  # Restore original plugins
  rm -f "$REAL_PLUGIN_DIR"/*.plugin.sh "$REAL_PLUGIN_DIR"/*.plugin.py \
        "$REAL_PLUGIN_DIR"/*.plugin.js "$REAL_PLUGIN_DIR"/*.plugin
  for f in "$BACKUP_DIR"/*; do
    [ -f "$f" ] && cp "$f" "$REAL_PLUGIN_DIR/" || true
  done
  rm -rf "$TEST_TMP"
}

@test "python deny plugin blocks tool call" {
  cp "$LANEKEEP_DIR/tests/fixtures/deny-plugin.py" "$REAL_PLUGIN_DIR/deny-test.plugin.py"
  chmod +x "$REAL_PLUGIN_DIR/deny-test.plugin.py"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "python allow plugin lets tool call through" {
  cp "$LANEKEEP_DIR/tests/fixtures/allow-plugin.py" "$REAL_PLUGIN_DIR/allow-test.plugin.py"
  chmod +x "$REAL_PLUGIN_DIR/allow-test.plugin.py"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "crashing python plugin is skipped (fail-open)" {
  cp "$LANEKEEP_DIR/tests/fixtures/crash-plugin.py" "$REAL_PLUGIN_DIR/crash-test.plugin.py"
  chmod +x "$REAL_PLUGIN_DIR/crash-test.plugin.py"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "non-executable polyglot plugin is skipped" {
  cp "$LANEKEEP_DIR/tests/fixtures/deny-plugin.py" "$REAL_PLUGIN_DIR/noexec-test.plugin.py"
  chmod -x "$REAL_PLUGIN_DIR/noexec-test.plugin.py"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "bash plugins still work alongside polyglot" {
  # Install both a bash allow and a polyglot allow plugin
  cp "$LANEKEEP_DIR/plugins.d/examples/docker-safety.plugin.sh" "$REAL_PLUGIN_DIR/docker-safety.plugin.sh"
  cp "$LANEKEEP_DIR/tests/fixtures/allow-plugin.py" "$REAL_PLUGIN_DIR/allow-test.plugin.py"
  chmod +x "$REAL_PLUGIN_DIR/allow-test.plugin.py"
  # Non-docker command should pass both
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}
