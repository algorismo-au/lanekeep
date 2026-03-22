#!/usr/bin/env bats
# Tests for stop notification hook

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"

  # Create state file with known values
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  now=$(date +%s)
  start=$((now - 120))  # 2 minutes ago
  printf '{"action_count":42,"start_epoch":%d}' "$start" > "$TEST_TMP/.lanekeep/state.json"

  # Create a trace file with some denies
  printf '{"decision":"allow"}\n{"decision":"deny"}\n{"decision":"deny"}\n{"decision":"allow"}\n' \
    > "$TEST_TMP/.lanekeep/traces/session-001.jsonl"

  # Create config
  printf '{"notifications":{"enabled":true,"on_stop":true,"min_session_seconds":5}}' \
    > "$TEST_TMP/lanekeep.json"

  export LANEKEEP_STATE_FILE="$TEST_TMP/.lanekeep/state.json"
  export LANEKEEP_TRACE_DIR="$TEST_TMP/.lanekeep/traces"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "stop hook: extracts action count from state file" {
  # Mock notify-send to capture the message
  export PATH="$TEST_TMP/bin:$PATH"
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/notify-send" << 'MOCK'
#!/bin/bash
echo "$2" > "$LANEKEEP_STATE_FILE.notify_msg"
MOCK
  chmod +x "$TEST_TMP/bin/notify-send"

  echo '{}' | "$LANEKEEP_DIR/hooks/stop.sh"
  msg=$(cat "$LANEKEEP_STATE_FILE.notify_msg" 2>/dev/null || true)
  [[ "$msg" == *"42 actions"* ]]
}

@test "stop hook: counts denies from trace file" {
  export PATH="$TEST_TMP/bin:$PATH"
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/notify-send" << 'MOCK'
#!/bin/bash
echo "$2" > "$LANEKEEP_STATE_FILE.notify_msg"
MOCK
  chmod +x "$TEST_TMP/bin/notify-send"

  echo '{}' | "$LANEKEEP_DIR/hooks/stop.sh"
  msg=$(cat "$LANEKEEP_STATE_FILE.notify_msg" 2>/dev/null || true)
  [[ "$msg" == *"2 denied"* ]]
}

@test "stop hook: includes elapsed time" {
  export PATH="$TEST_TMP/bin:$PATH"
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/notify-send" << 'MOCK'
#!/bin/bash
echo "$2" > "$LANEKEEP_STATE_FILE.notify_msg"
MOCK
  chmod +x "$TEST_TMP/bin/notify-send"

  echo '{}' | "$LANEKEEP_DIR/hooks/stop.sh"
  msg=$(cat "$LANEKEEP_STATE_FILE.notify_msg" 2>/dev/null || true)
  [[ "$msg" == *"2m"* ]]
}

@test "stop hook: graceful when state file missing" {
  rm -f "$LANEKEEP_STATE_FILE"
  # Short session (0 elapsed) suppressed — should exit 0 silently
  run bash -c 'echo "{}" | '"$LANEKEEP_DIR/hooks/stop.sh"
  [ "$status" -eq 0 ]
}

@test "stop hook: suppresses for short sessions" {
  now=$(date +%s)
  start=$((now - 2))  # 2 seconds ago — below min_session_seconds
  printf '{"action_count":1,"start_epoch":%d}' "$start" > "$LANEKEEP_STATE_FILE"

  export PATH="$TEST_TMP/bin:$PATH"
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/notify-send" << 'MOCK'
#!/bin/bash
echo "CALLED" > "$LANEKEEP_STATE_FILE.notify_called"
MOCK
  chmod +x "$TEST_TMP/bin/notify-send"

  echo '{}' | "$LANEKEEP_DIR/hooks/stop.sh"
  # Should NOT have called notify-send
  [ ! -f "$LANEKEEP_STATE_FILE.notify_called" ]
}

@test "stop hook: respects notifications.enabled=false" {
  printf '{"notifications":{"enabled":false}}' > "$TEST_TMP/lanekeep.json"

  export PATH="$TEST_TMP/bin:$PATH"
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/notify-send" << 'MOCK'
#!/bin/bash
echo "CALLED" > "$LANEKEEP_STATE_FILE.notify_called"
MOCK
  chmod +x "$TEST_TMP/bin/notify-send"

  echo '{}' | "$LANEKEEP_DIR/hooks/stop.sh"
  [ ! -f "$LANEKEEP_STATE_FILE.notify_called" ]
}

@test "stop hook: falls back to stderr when no notifier available" {
  # Set up mock bin directory with essential commands but NO notify-send
  mkdir -p "$TEST_TMP/bin"
  for cmd in jq date grep ls head cat bash printf tr rm uname; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ln -sf "$(command -v "$cmd")" "$TEST_TMP/bin/$cmd"
    fi
  done
  # Override PATH — no notify-send, no osascript
  SAVED_PATH="$PATH"
  export PATH="$TEST_TMP/bin"

  result=$(echo '{}' | "$LANEKEEP_DIR/hooks/stop.sh" 2>&1)
  export PATH="$SAVED_PATH"
  [[ "$result" == *"[LaneKeep]"* ]]
  [[ "$result" == *"42 actions"* ]]
}

@test "stop hook: graceful when trace dir empty" {
  rm -f "$TEST_TMP/.lanekeep/traces/"*.jsonl

  export PATH="$TEST_TMP/bin:$PATH"
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/notify-send" << 'MOCK'
#!/bin/bash
echo "$2" > "$LANEKEEP_STATE_FILE.notify_msg"
MOCK
  chmod +x "$TEST_TMP/bin/notify-send"

  echo '{}' | "$LANEKEEP_DIR/hooks/stop.sh"
  msg=$(cat "$LANEKEEP_STATE_FILE.notify_msg" 2>/dev/null || true)
  [[ "$msg" == *"0 denied"* ]]
}
