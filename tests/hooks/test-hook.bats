#!/usr/bin/env bats
# Tests for lanekeep/hooks/evaluate.sh (Claude Code PreToolUse hook bridge)

LANEKEEP_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  export LANEKEEP_DIR
  export PATH="$LANEKEEP_DIR/bin:$PATH"
  TEST_TMPDIR="$(mktemp -d)"
  export LANEKEEP_SOCKET="$TEST_TMPDIR/lanekeep-test.sock"
  export PROJECT_DIR="$TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR"
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
  "$LANEKEEP_DIR/bin/lanekeep-serve" "$@" >/dev/null 2>&1 &
  SERVER_PID=$!
  local tries=0
  while [ ! -S "$LANEKEEP_SOCKET" ] && [ $tries -lt 20 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
}

# --- AC3: LaneKeep Not Running — Graceful Degradation ---

@test "hook allows when LaneKeep not running (no socket)" {
  unset LANEKEEP_SOCKET
  export LANEKEEP_SOCKET="$TEST_TMPDIR/nonexistent.sock"
  export LANEKEEP_FAIL_POLICY="allow"
  run sh -c 'cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" | "$LANEKEEP_DIR/hooks/evaluate.sh"'
  [ "$status" -eq 0 ]
  # stdout should be empty (allow = no output)
  [ -z "$output" ] || [ "$(echo "$output" | grep -c hookSpecificOutput)" -eq 0 ]
}

@test "hook warns on stderr when LaneKeep not running" {
  export LANEKEEP_SOCKET="$TEST_TMPDIR/nonexistent.sock"
  export LANEKEEP_FAIL_POLICY="allow"
  STDERR_FILE="$TEST_TMPDIR/stderr.log"
  cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>"$STDERR_FILE"
  grep -qi "WARNING" "$STDERR_FILE"
}

# --- AC4: Stale Socket — Graceful Degradation ---

@test "hook allows when socket file exists but nothing listens" {
  # Create a file that looks like a socket but isn't listening
  touch "$LANEKEEP_SOCKET"
  export LANEKEEP_FAIL_POLICY="allow"
  run sh -c 'cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" | "$LANEKEEP_DIR/hooks/evaluate.sh"'
  [ "$status" -eq 0 ]
}

@test "hook warns on stderr when stale socket" {
  touch "$LANEKEEP_SOCKET"
  export LANEKEEP_FAIL_POLICY="allow"
  STDERR_FILE="$TEST_TMPDIR/stderr.log"
  cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>"$STDERR_FILE"
  grep -qi "WARNING" "$STDERR_FILE"
}

# --- AC1: LaneKeep Running — Allow ---

@test "hook exits 0 with no stdout when LaneKeep allows" {
  start_server
  STDERR_FILE="$TEST_TMPDIR/stderr.log"
  STDOUT=$(cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>"$STDERR_FILE")
  STATUS=$?
  [ "$STATUS" -eq 0 ]
  [ -z "$STDOUT" ]
}

# --- AC2: LaneKeep Running — Deny ---

@test "hook outputs hookSpecificOutput on deny" {
  start_server
  STDERR_FILE="$TEST_TMPDIR/stderr.log"
  STDOUT=$(cat "$LANEKEEP_DIR/tests/fixtures/hook-request-rm.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>"$STDERR_FILE")
  STATUS=$?
  [ "$STATUS" -eq 0 ]
  echo "$STDOUT" | jq -e '.hookSpecificOutput' >/dev/null 2>&1
}

@test "hook deny has permissionDecision deny" {
  start_server
  STDOUT=$(cat "$LANEKEEP_DIR/tests/fixtures/hook-request-rm.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null)
  DECISION=$(echo "$STDOUT" | jq -r '.hookSpecificOutput.permissionDecision')
  [ "$DECISION" = "deny" ]
}

# --- AC5: Deny Response Has permissionDecisionReason ---

@test "hook deny has non-empty permissionDecisionReason" {
  start_server
  STDOUT=$(cat "$LANEKEEP_DIR/tests/fixtures/hook-request-rm.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null)
  REASON=$(echo "$STDOUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  [ -n "$REASON" ]
  [ "$REASON" != "null" ]
}

# --- AC6: Configurable Timeout ---

@test "hook uses LANEKEEP_HOOK_TIMEOUT env var" {
  # We can verify the timeout is picked up by checking the script behavior
  # with a very short timeout against a non-responsive socket
  # Create a real Unix socket that accepts but never responds
  socat UNIX-LISTEN:"$LANEKEEP_SOCKET",fork EXEC:"sleep 10" &
  SOCAT_PID=$!
  local tries=0
  while [ ! -S "$LANEKEEP_SOCKET" ] && [ $tries -lt 20 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done

  export LANEKEEP_HOOK_TIMEOUT=1
  export LANEKEEP_FAIL_POLICY="allow"
  STDERR_FILE="$TEST_TMPDIR/stderr.log"
  # Should timeout and degrade gracefully within ~1s
  SECONDS=0
  cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>"$STDERR_FILE"
  ELAPSED=$SECONDS
  [ "$ELAPSED" -le 3 ]

  kill "$SOCAT_PID" 2>/dev/null || true
  wait "$SOCAT_PID" 2>/dev/null || true
}

# --- Socket resolution ---

@test "hook resolves socket from LANEKEEP_SOCKET env" {
  # Verify using custom socket path works end-to-end
  CUSTOM_SOCK="$TEST_TMPDIR/custom/my.sock"
  export LANEKEEP_SOCKET="$CUSTOM_SOCK"
  start_server
  [ -S "$CUSTOM_SOCK" ]
  STDOUT=$(cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null)
  STATUS=$?
  [ "$STATUS" -eq 0 ]
}

# --- Fallback Trace: audit gap coverage ---

@test "deny fail-policy writes fallback trace with correct decision and source" {
  export LANEKEEP_SOCKET="$TEST_TMPDIR/nonexistent.sock"
  export LANEKEEP_FAIL_POLICY="deny"
  cd "$PROJECT_DIR"
  cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null || true
  local trace_file="$PROJECT_DIR/.lanekeep/traces/hook-fallback.jsonl"
  [ -f "$trace_file" ]
  local entry
  entry=$(tail -1 "$trace_file")
  [ "$(printf '%s' "$entry" | jq -r '.decision')" = "deny" ]
  [ "$(printf '%s' "$entry" | jq -r '.source')" = "lanekeep-hook" ]
  [ "$(printf '%s' "$entry" | jq -r '.tool_name')" = "Read" ]
}

@test "allow fail-policy writes fallback trace with allow decision" {
  export LANEKEEP_SOCKET="$TEST_TMPDIR/nonexistent.sock"
  export LANEKEEP_FAIL_POLICY="allow"
  cd "$PROJECT_DIR"
  cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null || true
  local trace_file="$PROJECT_DIR/.lanekeep/traces/hook-fallback.jsonl"
  [ -f "$trace_file" ]
  local entry
  entry=$(tail -1 "$trace_file")
  [ "$(printf '%s' "$entry" | jq -r '.decision')" = "allow" ]
}

@test "fallback trace entry is valid JSON with tool_use_id" {
  export LANEKEEP_SOCKET="$TEST_TMPDIR/nonexistent.sock"
  export LANEKEEP_FAIL_POLICY="deny"
  cd "$PROJECT_DIR"
  cat "$LANEKEEP_DIR/tests/fixtures/hook-request-rm.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null || true
  local trace_file="$PROJECT_DIR/.lanekeep/traces/hook-fallback.jsonl"
  [ -f "$trace_file" ]
  local entry
  entry=$(tail -1 "$trace_file")
  # Valid JSON (jq exits non-zero on invalid)
  printf '%s' "$entry" | jq -e . >/dev/null
  [ "$(printf '%s' "$entry" | jq -r '.tool_use_id')" = "toolu_04JKL" ]
  [ "$(printf '%s' "$entry" | jq -r '.tool_name')" = "Bash" ]
}

@test "fallback trace creates trace dir with 0700 if missing" {
  export LANEKEEP_SOCKET="$TEST_TMPDIR/nonexistent.sock"
  export LANEKEEP_FAIL_POLICY="deny"
  cd "$PROJECT_DIR"
  # Ensure no traces dir exists
  [ ! -d "$PROJECT_DIR/.lanekeep/traces" ]
  cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null || true
  [ -d "$PROJECT_DIR/.lanekeep/traces" ]
  local perms
  perms=$(stat -c '%a' "$PROJECT_DIR/.lanekeep/traces")
  [ "$perms" = "700" ]
}

@test "stale socket writes fallback trace" {
  # Create a regular file where the socket should be (simulates stale socket)
  touch "$LANEKEEP_SOCKET"
  export LANEKEEP_FAIL_POLICY="allow"
  cd "$PROJECT_DIR"
  cat "$LANEKEEP_DIR/tests/fixtures/hook-request-read.json" \
    | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null || true
  local trace_file="$PROJECT_DIR/.lanekeep/traces/hook-fallback.jsonl"
  [ -f "$trace_file" ]
  local entry
  entry=$(tail -1 "$trace_file")
  [ "$(printf '%s' "$entry" | jq -r '.source')" = "lanekeep-hook" ]
  [ "$(printf '%s' "$entry" | jq -r '.event_type')" = "PreToolUse" ]
}
