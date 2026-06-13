#!/usr/bin/env bats
# Tests for network egress patterns (ssh, scp, nc, ncat, netcat, socat)

setup() {
  # Test lives at lanekeep/tests/rules/, so ../.. resolves to the lanekeep repo root.
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-network"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "network: ssh requires approval via rules" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"ssh user@host"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "network: scp requires approval via rules" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"scp file.txt user@host:/tmp/"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "network: nc requires approval via rules" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"nc localhost 8080"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "network: ncat requires approval via rules" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"ncat -l 4444"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "network: netcat requires approval via rules" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"netcat -z host 80"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "network: socat requires approval via rules" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"socat TCP:host:80 STDOUT"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "network: curl still requires approval" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "network: wget still requires approval" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"wget https://example.com"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "network: reason includes intent for ssh" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"ssh user@host"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [[ "$reason" == *"Network"* ]] || [[ "$reason" == *"network"* ]] || [[ "$reason" == *"approval"* ]]
}

@test "network: non-network Bash commands are allowed" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "network: egress patterns in codediff ask_patterns" {
  local patterns
  patterns=$(jq -r '.evaluators.codediff.ask_patterns[]' "$LANEKEEP_DIR/defaults/lanekeep.json")
  echo "$patterns" | grep -qF "ssh "
  echo "$patterns" | grep -qF "scp "
  echo "$patterns" | grep -qF "nc "
  echo "$patterns" | grep -qF "ncat "
  echo "$patterns" | grep -qF "netcat "
  echo "$patterns" | grep -qF "socat "
}
