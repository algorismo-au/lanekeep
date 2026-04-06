#!/usr/bin/env bats
# Tests for multi-agent concurrent access to a single LaneKeep sidecar.
# Validates that multiple agents (including worktree-based subagents)
# can share one sidecar without "sidecar unavailable" errors.

LANEKEEP_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  export LANEKEEP_DIR
  export PATH="$LANEKEEP_DIR/bin:$PATH"
  TEST_TMPDIR="$(mktemp -d)"
  export LANEKEEP_SOCKET="$TEST_TMPDIR/lanekeep-test.sock"
  export PROJECT_DIR="$TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR/.lanekeep/traces"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$PROJECT_DIR/lanekeep.json"
  SERVER_PID=""
}

teardown() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    pkill -P "$SERVER_PID" 2>/dev/null || true
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMPDIR"
  return 0
}

start_server() {
  cd "$PROJECT_DIR"
  "$LANEKEEP_DIR/bin/lanekeep-serve" "$@" </dev/null >/dev/null 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
  SERVER_PID=$!
  local tries=0
  while [ ! -S "$LANEKEEP_SOCKET" ] && [ $tries -lt 30 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
  [ -S "$LANEKEEP_SOCKET" ] || { echo "Server failed to start" >&2; return 1; }
}

send_request() {
  # $1 = fixture file, $2 = optional session_id override
  local fixture="$1"
  local session_id="${2:-}"
  local input
  input=$(cat "$fixture")
  if [ -n "$session_id" ]; then
    input=$(printf '%s' "$input" | jq --arg sid "$session_id" '.session_id = $sid')
  fi
  printf '%s' "$input" | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null
}

# --- Concurrent requests to single sidecar ---

@test "10 concurrent agents get responses (no sidecar unavailable)" {
  start_server
  local fixture="$LANEKEEP_DIR/tests/fixtures/hook-request-read.json"
  local pids=()
  local outdir="$TEST_TMPDIR/results"
  mkdir -p "$outdir"

  # Fire 10 parallel requests with different session IDs
  for i in $(seq 1 10); do
    (
      result=$(send_request "$fixture" "agent-$i")
      echo "$result" > "$outdir/$i.out"
      echo "$?" > "$outdir/$i.rc"
    ) &
    pids+=($!)
  done

  # Wait for all
  local failed=0
  for pid in "${pids[@]}"; do
    wait "$pid" || failed=$((failed + 1))
  done

  # All should succeed (exit 0)
  [ "$failed" -eq 0 ]

  # No result should contain "deny" due to sidecar unavailable
  for i in $(seq 1 10); do
    if [ -f "$outdir/$i.out" ] && [ -s "$outdir/$i.out" ]; then
      # If there's output, it should not be a sidecar-unreachable deny
      ! grep -q "unreachable" "$outdir/$i.out"
    fi
  done
}

@test "concurrent agents each get correct allow/deny decisions" {
  start_server
  local allow_fixture="$LANEKEEP_DIR/tests/fixtures/hook-request-read.json"
  local deny_fixture="$LANEKEEP_DIR/tests/fixtures/hook-request-rm.json"
  local outdir="$TEST_TMPDIR/results"
  mkdir -p "$outdir"
  local pids=()

  # Mix of allow and deny requests in parallel
  for i in $(seq 1 5); do
    ( send_request "$allow_fixture" "allow-agent-$i" > "$outdir/allow-$i.out" 2>/dev/null ) &
    pids+=($!)
    ( send_request "$deny_fixture" "deny-agent-$i" > "$outdir/deny-$i.out" 2>/dev/null ) &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  # Allow results: should be empty stdout (no hookSpecificOutput = allow)
  for i in $(seq 1 5); do
    if [ -s "$outdir/allow-$i.out" ]; then
      ! grep -q '"permissionDecision":"deny"' "$outdir/allow-$i.out" \
        || { echo "allow-agent-$i was denied"; return 1; }
    fi
  done

  # Deny results: should contain deny decision
  for i in $(seq 1 5); do
    [ -s "$outdir/deny-$i.out" ] || { echo "deny-agent-$i got empty response"; return 1; }
    grep -q '"deny"' "$outdir/deny-$i.out" \
      || { echo "deny-agent-$i was not denied"; return 1; }
  done
}

# --- Worktree agent: different PWD, shared socket ---

@test "agent in different PWD connects to shared sidecar via LANEKEEP_SOCKET" {
  start_server
  local fixture="$LANEKEEP_DIR/tests/fixtures/hook-request-read.json"

  # Simulate a worktree subagent with a different PWD
  local worktree="$TEST_TMPDIR/worktree-abc"
  mkdir -p "$worktree"

  # LANEKEEP_SOCKET is already set to the shared socket path
  # This should work — the hook uses LANEKEEP_SOCKET, not PWD
  cd "$worktree"
  run send_request "$fixture" "worktree-agent-1"
  [ "$status" -eq 0 ]
  # Should not be a sidecar-unavailable deny
  if [ -n "$output" ]; then
    ! echo "$output" | grep -q "unreachable"
  fi
}

@test "agent WITHOUT LANEKEEP_SOCKET in child of project dir finds socket by walking up" {
  # Start server with socket at standard project location (not custom LANEKEEP_SOCKET)
  export LANEKEEP_SOCKET="$PROJECT_DIR/.lanekeep/lanekeep.sock"
  start_server
  local fixture="$LANEKEEP_DIR/tests/fixtures/hook-request-read.json"

  # Simulate worktree subagent nested inside the project dir (no env vars set)
  local subdir="$PROJECT_DIR/src/deep/nested"
  mkdir -p "$subdir"

  # Unset both — hook must walk up from PWD to find .lanekeep/lanekeep.sock
  unset LANEKEEP_SOCKET
  unset PROJECT_DIR

  cd "$subdir"
  run send_request "$fixture" "walk-up-agent"
  [ "$status" -eq 0 ]
  # Should NOT get a sidecar-unavailable deny
  if [ -n "$output" ]; then
    ! echo "$output" | grep -q "unreachable"
  fi
}

@test "agent in unrelated dir WITHOUT LANEKEEP_SOCKET gets fail-policy (expected)" {
  start_server
  local fixture="$LANEKEEP_DIR/tests/fixtures/hook-request-read.json"

  # Truly unrelated directory — no .lanekeep/ anywhere in ancestry
  local unrelated="$TEST_TMPDIR/unrelated-dir"
  mkdir -p "$unrelated"

  unset LANEKEEP_SOCKET
  unset PROJECT_DIR
  export LANEKEEP_FAIL_POLICY="allow"

  cd "$unrelated"
  STDERR_FILE="$TEST_TMPDIR/stderr-unrelated.log"
  run bash -c 'cat "'"$fixture"'" | "'"$LANEKEEP_DIR"'/hooks/evaluate.sh" 2>"'"$STDERR_FILE"'"'

  # Unrelated dir has no socket in ancestry — should warn
  grep -qi "WARNING\|not running\|unreachable" "$STDERR_FILE" \
    || { echo "Expected warning about missing sidecar"; return 1; }
}

# --- Second sidecar start attempt is handled gracefully ---

@test "second lanekeep-serve exits non-destructively when sidecar already running" {
  start_server

  # Try to start a second sidecar — should fail but not kill the first
  run "$LANEKEEP_DIR/bin/lanekeep-serve" </dev/null 2>&1
  [ "$status" -ne 0 ] || echo "$output" | grep -qi "already running"

  # Original sidecar should still be alive and responding
  local fixture="$LANEKEEP_DIR/tests/fixtures/hook-request-read.json"
  run send_request "$fixture" "post-double-start"
  [ "$status" -eq 0 ]
  if [ -n "$output" ]; then
    ! echo "$output" | grep -q "unreachable"
  fi
}

# --- Burst load ---

@test "15 concurrent requests under burst load" {
  start_server
  local fixture="$LANEKEEP_DIR/tests/fixtures/hook-request-read.json"
  local outdir="$TEST_TMPDIR/burst"
  mkdir -p "$outdir"
  local pids=()
  local count=15

  for i in $(seq 1 "$count"); do
    ( send_request "$fixture" "burst-$i" > "$outdir/$i.out" 2>"$outdir/$i.err" ; echo "$?" > "$outdir/$i.rc" ) &
    pids+=($!)
    # Stagger launches to avoid overwhelming CI runners
    [ $((i % 5)) -eq 0 ] && sleep 0.1
  done

  local failed=0
  for pid in "${pids[@]}"; do
    wait "$pid" || failed=$((failed + 1))
  done

  # Count how many got sidecar-unavailable errors
  local unavailable=0
  for i in $(seq 1 "$count"); do
    if [ -f "$outdir/$i.out" ] && grep -q "unreachable" "$outdir/$i.out" 2>/dev/null; then
      unavailable=$((unavailable + 1))
    fi
    if [ -f "$outdir/$i.err" ] && grep -q "not running" "$outdir/$i.err" 2>/dev/null; then
      unavailable=$((unavailable + 1))
    fi
  done

  echo "# Burst results: $failed failed exits, $unavailable unavailable errors" >&3
  [ "$unavailable" -eq 0 ]
}
