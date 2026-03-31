#!/usr/bin/env bats
# Tests for the lanekeep-serve watchdog (auto-restart on socat crash)

LANEKEEP_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  export LANEKEEP_DIR
  export PATH="$LANEKEEP_DIR/bin:$PATH"
  TEST_TMPDIR="$(mktemp -d)"
  export LANEKEEP_SOCKET="$TEST_TMPDIR/lanekeep-test.sock"
  export PROJECT_DIR="$TEST_TMPDIR/project"
  mkdir -p "$PROJECT_DIR"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$PROJECT_DIR/lanekeep.json"
  PIDFILE="$(dirname "$LANEKEEP_SOCKET")/lanekeep-serve.pid"
  LOGFILE="$TEST_TMPDIR/serve.log"
  SERVER_PID=""
}

teardown() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMPDIR"
  return 0
}

start_server() {
  cd "$PROJECT_DIR"
  "$LANEKEEP_DIR/bin/lanekeep-serve" "$@" </dev/null >/dev/null 2>"$LOGFILE" 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
  SERVER_PID=$!
  local tries=0
  while [ ! -S "$LANEKEEP_SOCKET" ] && [ $tries -lt 30 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
  [ -S "$LANEKEEP_SOCKET" ] || { echo "Server failed to start. Log:"; cat "$LOGFILE"; return 1; }
}

get_socat_pid() {
  [ -f "$PIDFILE" ] && sed -n '2p' "$PIDFILE" 2>/dev/null || echo ""
}

wait_for_new_socat() {
  local old_pid="$1"
  local tries=0
  while [ $tries -lt 40 ]; do
    local new_pid
    new_pid=$(get_socat_pid)
    if [ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ] && kill -0 "$new_pid" 2>/dev/null; then
      echo "$new_pid"
      return 0
    fi
    sleep 0.2
    tries=$((tries + 1))
  done
  echo ""
  return 1
}

@test "watchdog: SIGTERM causes clean shutdown without restart" {
  start_server
  [ -S "$LANEKEEP_SOCKET" ]

  kill "$SERVER_PID"
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""

  sleep 0.3

  ! grep -q "Restarting" "$LOGFILE"
  grep -q "Sidecar stopped" "$LOGFILE"
}

@test "watchdog: socat crash triggers restart" {
  start_server

  SOCAT_PID_1=$(get_socat_pid)
  [ -n "$SOCAT_PID_1" ]

  kill -9 "$SOCAT_PID_1" 2>/dev/null || true

  SOCAT_PID_2=$(wait_for_new_socat "$SOCAT_PID_1") || {
    echo "Restart did not happen. Log:"; cat "$LOGFILE"; return 1
  }

  [ "$SOCAT_PID_2" != "$SOCAT_PID_1" ]
  grep -q "Restarting" "$LOGFILE"
  grep -q "Socat restarted" "$LOGFILE"
  [ -S "$LANEKEEP_SOCKET" ]

  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""
}

@test "watchdog: PID file shell PID unchanged after restart" {
  start_server

  SOCAT_PID_1=$(get_socat_pid)
  SHELL_PID_1=$(head -1 "$PIDFILE")

  kill -9 "$SOCAT_PID_1" 2>/dev/null || true

  SOCAT_PID_2=$(wait_for_new_socat "$SOCAT_PID_1") || {
    echo "Restart did not happen. Log:"; cat "$LOGFILE"; return 1
  }

  SHELL_PID_2=$(head -1 "$PIDFILE")
  [ "$SHELL_PID_1" = "$SHELL_PID_2" ]
  [ "$SOCAT_PID_1" != "$SOCAT_PID_2" ]

  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""
}

@test "watchdog: LANEKEEP_NO_WATCHDOG=1 disables restart" {
  export LANEKEEP_NO_WATCHDOG=1
  start_server

  SOCAT_PID_1=$(get_socat_pid)
  kill -9 "$SOCAT_PID_1" 2>/dev/null || true

  local tries=0
  while kill -0 "$SERVER_PID" 2>/dev/null && [ $tries -lt 20 ]; do
    sleep 0.2
    tries=$((tries + 1))
  done

  ! kill -0 "$SERVER_PID" 2>/dev/null
  ! grep -q "Restarting" "$LOGFILE"
  SERVER_PID=""
}

@test "watchdog: max restarts exhausted causes exit" {
  export LANEKEEP_WATCHDOG_MAX_RESTARTS=2
  start_server

  for _round in 1 2 3; do
    local spid=""
    local tries=0
    while [ $tries -lt 30 ]; do
      spid=$(get_socat_pid)
      if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
        break
      fi
      sleep 0.2
      tries=$((tries + 1))
    done
    kill -0 "$SERVER_PID" 2>/dev/null || break
    [ -n "$spid" ] && kill -9 "$spid" 2>/dev/null || true
    sleep 0.5
  done

  local tries=0
  while kill -0 "$SERVER_PID" 2>/dev/null && [ $tries -lt 50 ]; do
    sleep 0.3
    tries=$((tries + 1))
  done

  ! kill -0 "$SERVER_PID" 2>/dev/null || { echo "Server still alive. Log:"; cat "$LOGFILE"; return 1; }
  grep -q "giving up" "$LOGFILE" || { echo "No 'giving up'. Log:"; cat "$LOGFILE"; return 1; }
  SERVER_PID=""
}
