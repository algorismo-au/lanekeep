#!/usr/bin/env bats
# Regression test for sidecar lock contention under concurrent load
# Verifies that exec 1>&- delivers responses immediately even when bookkeeping stalls.

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-concurrency"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/.lanekeep/cumulative.json"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  SOCK="$TEST_TMP/lk.sock"
}

teardown() {
  # Kill any lingering socat listeners
  [ -n "${SOCAT_PID:-}" ] && kill "$SOCAT_PID" 2>/dev/null; wait "$SOCAT_PID" 2>/dev/null
  rm -rf "$TEST_TMP" ; return 0
}

@test "exec 1>&- delivers response before handler exits" {
  # Create a script that simulates: write response, close stdout, stall on bookkeeping
  cat > "$TEST_TMP/slow-handler.sh" << 'HANDLER'
#!/bin/bash
echo "RESPONSE"
exec 1>&-
sleep 10
HANDLER
  chmod +x "$TEST_TMP/slow-handler.sh"

  socat -t 3 UNIX-LISTEN:"$SOCK",fork \
    EXEC:"$TEST_TMP/slow-handler.sh",pipes &
  SOCAT_PID=$!
  sleep 0.3  # let listener bind

  # Client with 2s timeout — should get response in ~0s, not 10s
  result=$(echo REQ | timeout 3 socat -t 2 - UNIX-CONNECT:"$SOCK")
  [ "$result" = "RESPONSE" ]
}

@test "two parallel handler invocations both complete within timeout" {
  # Start socat with the real handler
  socat UNIX-LISTEN:"$SOCK",fork \
    EXEC:"$LANEKEEP_DIR/bin/lanekeep-handler",pipes &
  SOCAT_PID=$!
  sleep 0.3  # let listener bind

  REQ='{"tool_name":"Read","tool_input":{"file_path":"x"}}'

  # Fire two requests in parallel, each with 4s timeout
  echo "$REQ" | timeout 4 socat -t 2 - UNIX-CONNECT:"$SOCK" > "$TEST_TMP/out1" &
  PID1=$!
  echo "$REQ" | timeout 4 socat -t 2 - UNIX-CONNECT:"$SOCK" > "$TEST_TMP/out2" &
  PID2=$!

  wait "$PID1"
  rc1=$?
  wait "$PID2"
  rc2=$?

  # Both should exit 0 (not timeout)
  [ "$rc1" -eq 0 ]
  [ "$rc2" -eq 0 ]

  # Both should return valid allow decisions
  d1=$(jq -r '.decision' "$TEST_TMP/out1")
  d2=$(jq -r '.decision' "$TEST_TMP/out2")
  [ "$d1" = "allow" ]
  [ "$d2" = "allow" ]
}
