#!/usr/bin/env bats
# Tests for the webhook plugin adapter (sourced directly)

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  source "$LANEKEEP_DIR/plugins.d/examples/webhook.plugin.sh"
}

teardown() {
  [ -f "$TEST_TMP/mock.pid" ] && kill "$(cat "$TEST_TMP/mock.pid")" 2>/dev/null || true
  rm -rf "$TEST_TMP"
}

_start_mock() {
  local response="$1"
  local portfile="$TEST_TMP/mock.port"
  local script="$TEST_TMP/mock.py"
  cat > "$script" <<EOF
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        self.rfile.read(length)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(sys.argv[1].encode())
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 0), H)
with open(sys.argv[2], 'w') as f:
    f.write(str(srv.server_address[1]))
for _ in range(3):
    srv.handle_request()
EOF
  python3 "$script" "$response" "$portfile" </dev/null >/dev/null 2>&1 &
  echo "$!" > "$TEST_TMP/mock.pid"
  local i=0
  while [ ! -f "$portfile" ] && [ $i -lt 50 ]; do
    sleep 0.05
    i=$((i + 1))
  done
  cat "$portfile"
}

@test "webhook deny response returns deny" {
  port=$(_start_mock '{"passed":false,"reason":"webhook denied","decision":"deny"}')
  export LANEKEEP_WEBHOOK_URL="http://127.0.0.1:$port"
  webhook_eval "Bash" '{"command":"rm -rf /"}' || true
  [ "$WEBHOOK_PASSED" = "false" ]
  [ "$WEBHOOK_DECISION" = "deny" ]
  [[ "$WEBHOOK_REASON" == *"webhook denied"* ]]
}

@test "webhook allow response returns pass" {
  port=$(_start_mock '{"passed":true,"reason":"","decision":"deny"}')
  export LANEKEEP_WEBHOOK_URL="http://127.0.0.1:$port"
  webhook_eval "Read" '{"file_path":"x"}'
  [ "$WEBHOOK_PASSED" = "true" ]
}

@test "webhook unreachable URL fails open" {
  export LANEKEEP_WEBHOOK_URL="http://127.0.0.1:19999"
  webhook_eval "Read" '{"file_path":"x"}'
  [ "$WEBHOOK_PASSED" = "true" ]
}

@test "webhook URL not set passes (no-op)" {
  unset LANEKEEP_WEBHOOK_URL
  webhook_eval "Read" '{"file_path":"x"}'
  [ "$WEBHOOK_PASSED" = "true" ]
}

@test "webhook timeout fails open" {
  export LANEKEEP_WEBHOOK_URL="http://10.255.255.1:9999"
  export LANEKEEP_WEBHOOK_TIMEOUT="1"
  webhook_eval "Read" '{"file_path":"x"}'
  [ "$WEBHOOK_PASSED" = "true" ]
}
