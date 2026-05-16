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

@test "listener keeps serving after a client drops mid-response" {
  # If a client closes its socket before reading, the handler subprocess gets
  # SIGPIPE on its next write. Without `trap '' PIPE` in bin/lanekeep-handler,
  # that handler dies with exit 141 — fine in isolation. The real failure mode
  # we're guarding against is the *listener* failing to accept subsequent
  # connections because the prior fork crashed messily.
  socat UNIX-LISTEN:"$SOCK",fork \
    EXEC:"$LANEKEEP_DIR/bin/lanekeep-handler",pipes &
  SOCAT_PID=$!
  sleep 0.3  # let listener bind

  REQ='{"tool_name":"Read","tool_input":{"file_path":"x"}}'

  # Client A: send the request, then drop the connection within 300ms — the
  # handler will be mid-write when the socket goes away. Errors silenced; the
  # point is the side-effect on the server, not this client's exit code.
  echo "$REQ" | timeout 0.3 socat - UNIX-CONNECT:"$SOCK" > /dev/null 2>&1 || true

  # Brief pause so socat can reap the crashed fork (if it did crash).
  sleep 0.2

  # Client B: normal request — listener must still accept and serve.
  result=$(echo "$REQ" | timeout 3 socat -t 2 - UNIX-CONNECT:"$SOCK")
  decision=$(printf '%s' "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]

  # Listener process itself must still be alive.
  kill -0 "$SOCAT_PID"
}
