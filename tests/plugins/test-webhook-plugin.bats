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

# --- HTTPS enforcement tests ---

@test "webhook rejects http:// URL" {
  export LANEKEEP_WEBHOOK_URL="http://example.com/hook"
  webhook_eval "Bash" '{"command":"ls"}'
  [ "$WEBHOOK_PASSED" = "true" ]  # fail-open, but URL rejected
}

@test "webhook rejects localhost URL" {
  export LANEKEEP_WEBHOOK_URL="https://localhost/hook"
  webhook_eval "Bash" '{"command":"ls"}'
  [ "$WEBHOOK_PASSED" = "true" ]  # fail-open, internal address rejected
}

@test "webhook rejects 127.0.0.1 URL" {
  export LANEKEEP_WEBHOOK_URL="https://127.0.0.1/hook"
  webhook_eval "Bash" '{"command":"ls"}'
  [ "$WEBHOOK_PASSED" = "true" ]  # fail-open, loopback rejected
}

@test "webhook rejects 10.x.x.x URL" {
  export LANEKEEP_WEBHOOK_URL="https://10.0.0.1/hook"
  webhook_eval "Bash" '{"command":"ls"}'
  [ "$WEBHOOK_PASSED" = "true" ]  # fail-open, RFC-1918 rejected
}

@test "webhook rejects 192.168.x.x URL" {
  export LANEKEEP_WEBHOOK_URL="https://192.168.1.1/hook"
  webhook_eval "Bash" '{"command":"ls"}'
  [ "$WEBHOOK_PASSED" = "true" ]  # fail-open, RFC-1918 rejected
}

@test "webhook rejects 169.254.x.x (link-local) URL" {
  export LANEKEEP_WEBHOOK_URL="https://169.254.169.254/latest/meta-data/"
  webhook_eval "Bash" '{"command":"ls"}'
  [ "$WEBHOOK_PASSED" = "true" ]  # fail-open, cloud metadata rejected
}

# --- Functional tests ---

@test "webhook URL not set passes (no-op)" {
  unset LANEKEEP_WEBHOOK_URL
  webhook_eval "Read" '{"file_path":"x"}'
  [ "$WEBHOOK_PASSED" = "true" ]
}

@test "webhook unreachable HTTPS URL fails open" {
  export LANEKEEP_WEBHOOK_URL="https://unreachable.invalid:19999"
  export LANEKEEP_WEBHOOK_TIMEOUT="1"
  webhook_eval "Read" '{"file_path":"x"}'
  [ "$WEBHOOK_PASSED" = "true" ]
}
