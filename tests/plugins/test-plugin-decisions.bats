#!/usr/bin/env bats
# Tests for plugin warn/ask/deny decision handling

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-plugin-decisions"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  # Handler hardcodes $LANEKEEP_DIR/plugins.d — use backup/restore for isolation
  REAL_PLUGIN_DIR="$LANEKEEP_DIR/plugins.d"
  BACKUP_DIR="$TEST_TMP/plugins-backup"
  mkdir -p "$BACKUP_DIR"

  # Save any existing active plugins
  for f in "$REAL_PLUGIN_DIR"/*.plugin.sh "$REAL_PLUGIN_DIR"/*.plugin.py \
           "$REAL_PLUGIN_DIR"/*.plugin.js "$REAL_PLUGIN_DIR"/*.plugin; do
    [ -f "$f" ] && cp "$f" "$BACKUP_DIR/" || true
  done

  # Clean real plugin dir for test isolation
  rm -f "$REAL_PLUGIN_DIR"/*.plugin.sh "$REAL_PLUGIN_DIR"/*.plugin.py \
        "$REAL_PLUGIN_DIR"/*.plugin.js "$REAL_PLUGIN_DIR"/*.plugin

  PLUGIN_DIR="$REAL_PLUGIN_DIR"
  export PLUGIN_DIR
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

_install_plugin() {
  local name="$1" decision="$2" reason="$3"
  local upper
  upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
  cat > "$PLUGIN_DIR/_test-${name}.plugin.sh" <<PLUGIN
#!/usr/bin/env bash
_TEST_${upper}_PASSED=true
_TEST_${upper}_REASON=""
_TEST_${upper}_DECISION="deny"

_test_${name//-/_}_eval() {
  _TEST_${upper}_PASSED=false
  _TEST_${upper}_REASON="$reason"
  _TEST_${upper}_DECISION="$decision"
  return 1
}

LANEKEEP_PLUGIN_EVALS="\${LANEKEEP_PLUGIN_EVALS:-} _test_${name//-/_}_eval"
PLUGIN
}

@test "plugin deny blocks tool call" {
  _install_plugin "deny" "deny" "test deny reason"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "plugin ask produces ask decision" {
  _install_plugin "ask" "ask" "test ask reason"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "plugin warn produces warn decision" {
  _install_plugin "warn" "warn" "test warn reason"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  warn=$(printf '%s' "$output" | jq -r '.warn')
  [ "$decision" = "warn" ]
  [[ "$warn" == *"test warn reason"* ]]
}

@test "deny + ask = deny wins" {
  _install_plugin "ask" "ask" "ask reason"
  _install_plugin "deny" "deny" "deny reason"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "two warns concatenate reasons" {
  _install_plugin "warn" "warn" "first warning"
  _install_plugin "warn2" "warn" "second warning"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  warn=$(printf '%s' "$output" | jq -r '.warn')
  [ "$decision" = "warn" ]
  [[ "$warn" == *"first warning"* ]]
  [[ "$warn" == *"second warning"* ]]
}
