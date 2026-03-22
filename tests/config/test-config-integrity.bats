#!/usr/bin/env bats
# Tests for config drift detection (integrity hash verification)

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  source "$LANEKEEP_DIR/lib/config.sh"

  TEST_TMP="$(mktemp -d)"

  # Create a test config
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "rules": [],
  "policies": {},
  "hard_blocks": [],
  "budget": {"max_actions": 500, "max_tokens": null, "timeout_seconds": 3600}
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

# ── 1. Passes when config unchanged ──

@test "config integrity: passes when config unchanged" {
  LANEKEEP_CONFIG_HASH=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  export LANEKEEP_CONFIG_HASH
  verify_config_integrity
  [ "$INTEGRITY_PASSED" = "true" ]
  [ -z "$INTEGRITY_REASON" ]
}

# ── 2. Denies when hash mismatches ──

@test "config integrity: denies when hash mismatches" {
  LANEKEEP_CONFIG_HASH="0000000000000000000000000000000000000000000000000000000000000000"
  export LANEKEEP_CONFIG_HASH
  verify_config_integrity || true
  [ "$INTEGRITY_PASSED" = "false" ]
  [[ "$INTEGRITY_REASON" == *"Config integrity check failed"* ]]
}

# ── 3. verify_config_integrity returns 0 for matching hash ──

@test "config integrity: returns 0 for matching hash" {
  LANEKEEP_CONFIG_HASH=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  export LANEKEEP_CONFIG_HASH
  run verify_config_integrity
  [ "$status" -eq 0 ]
}

# ── 4. verify_config_integrity returns 1 after file modification ──

@test "config integrity: returns 1 after file modification" {
  LANEKEEP_CONFIG_HASH=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  export LANEKEEP_CONFIG_HASH
  # Modify the config
  echo '{"rules":[],"policies":{},"tampered":true}' > "$LANEKEEP_CONFIG_FILE"
  verify_config_integrity || true
  [ "$INTEGRITY_PASSED" = "false" ]
  [[ "$INTEGRITY_REASON" == *"modified since session start"* ]]
}

# ── 5. Skips gracefully when LANEKEEP_CONFIG_HASH is unset ──

@test "config integrity: skips when LANEKEEP_CONFIG_HASH is unset" {
  unset LANEKEEP_CONFIG_HASH
  verify_config_integrity
  # Should return 0 (pass) — no hash means no check
  [ $? -eq 0 ]
}

# ── 6. Trace includes ConfigIntegrity evaluator on failure ──

@test "config integrity: handler includes ConfigIntegrity in results on failure" {
  source "$LANEKEEP_DIR/lib/eval-hardblock.sh"
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
  source "$LANEKEEP_DIR/lib/eval-schema.sh"
  source "$LANEKEEP_DIR/lib/eval-codediff.sh"
  source "$LANEKEEP_DIR/lib/eval-budget.sh"
  source "$LANEKEEP_DIR/lib/eval-semantic.sh"
  source "$LANEKEEP_DIR/lib/eval-result-transform.sh"
  source "$LANEKEEP_DIR/lib/dispatcher.sh"
  source "$LANEKEEP_DIR/lib/trace.sh"

  # Set up a valid trace file
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_STATE_FILE="$TEST_TMP/.lanekeep/state.json"
  echo '{"action_count":0,"token_count":0,"start_epoch":0}' > "$LANEKEEP_STATE_FILE"

  # Set a wrong hash to trigger integrity failure
  export LANEKEEP_CONFIG_HASH="badhash000000000000000000000000000000000000000000000000000000000"

  local result
  result=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  echo "$result" | jq -e '.decision == "deny"'
  echo "$result" | jq -r '.reason' | grep -q "Config integrity"
}

# ── 7. Hash file with matching hash passes ──

@test "config integrity: hash file with matching hash passes" {
  local correct_hash
  correct_hash=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  # Write correct hash to hash file
  mkdir -p "$TEST_TMP/.lanekeep"
  printf '%s\n' "$correct_hash" > "$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH_FILE="$TEST_TMP/.lanekeep/config_hash"
  # Set a stale env var hash — hash file should take precedence
  export LANEKEEP_CONFIG_HASH="stale0000000000000000000000000000000000000000000000000000000000"
  # Force mtime mismatch so we don't hit the fast path
  export LANEKEEP_CONFIG_MTIME="0"
  verify_config_integrity
  [ "$INTEGRITY_PASSED" = "true" ]
  [ -z "$INTEGRITY_REASON" ]
}

# ── 8. Hash file takes precedence over stale env var ──

@test "config integrity: hash file takes precedence over stale env var" {
  local correct_hash
  correct_hash=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  # Hash file has the right hash
  mkdir -p "$TEST_TMP/.lanekeep"
  printf '%s\n' "$correct_hash" > "$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH_FILE="$TEST_TMP/.lanekeep/config_hash"
  # Env var has an old/wrong hash
  export LANEKEEP_CONFIG_HASH="0000000000000000000000000000000000000000000000000000000000000000"
  export LANEKEEP_CONFIG_MTIME="0"
  run verify_config_integrity
  [ "$status" -eq 0 ]
}

# ── 9. Config modified without hash file update is still denied ──

@test "config integrity: config modified without hash file update is denied" {
  local original_hash
  original_hash=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  mkdir -p "$TEST_TMP/.lanekeep"
  printf '%s\n' "$original_hash" > "$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH_FILE="$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH="$original_hash"
  # Back-date hash file so the tampered config is definitively newer (avoids mtime fast-path race)
  touch -d '2 seconds ago' "$TEST_TMP/.lanekeep/config_hash"
  # Tamper with config but do NOT update hash file
  echo '{"rules":[],"tampered":true}' > "$LANEKEEP_CONFIG_FILE"
  verify_config_integrity || true
  [ "$INTEGRITY_PASSED" = "false" ]
  [[ "$INTEGRITY_REASON" == *"Config integrity check failed"* ]]
}

# ── 10. Missing hash file falls back to env var ──

@test "config integrity: missing hash file falls back to env var" {
  local correct_hash
  correct_hash=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  export LANEKEEP_CONFIG_HASH="$correct_hash"
  # Point to a non-existent hash file
  export LANEKEEP_CONFIG_HASH_FILE="$TEST_TMP/.lanekeep/nonexistent_hash"
  export LANEKEEP_CONFIG_MTIME="0"
  verify_config_integrity
  [ "$INTEGRITY_PASSED" = "true" ]
  [ -z "$INTEGRITY_REASON" ]
}

# ── 11. Symlink hash file is denied ──

@test "config integrity: symlink hash file is denied" {
  local correct_hash
  correct_hash=$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)
  mkdir -p "$TEST_TMP/.lanekeep"
  # Write correct hash to a target, then symlink config_hash to it
  printf '%s\n' "$correct_hash" > "$TEST_TMP/.lanekeep/real_hash"
  ln -sf "$TEST_TMP/.lanekeep/real_hash" "$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH_FILE="$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH="$correct_hash"
  export LANEKEEP_CONFIG_MTIME="0"
  verify_config_integrity || true
  [ "$INTEGRITY_PASSED" = "false" ]
  [[ "$INTEGRITY_REASON" == *"symlink"* ]]
}

# ── 12. Invalid hash format in file is denied ──

@test "config integrity: invalid hash format in file is denied" {
  mkdir -p "$TEST_TMP/.lanekeep"
  printf 'NOT-A-VALID-HEX-HASH\n' > "$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH_FILE="$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH="$(sha256sum "$LANEKEEP_CONFIG_FILE" | cut -d' ' -f1)"
  export LANEKEEP_CONFIG_MTIME="0"
  # Ensure config is newer than hash file so -nt fast-path is not taken
  touch "$LANEKEEP_CONFIG_FILE"
  verify_config_integrity || true
  [ "$INTEGRITY_PASSED" = "false" ]
  [[ "$INTEGRITY_REASON" == *"invalid format"* ]]
}

# ── 13. Empty hash file does not silently fall back to env var ──

@test "config integrity: empty hash file falls back to env var (no file content)" {
  mkdir -p "$TEST_TMP/.lanekeep"
  : > "$TEST_TMP/.lanekeep/config_hash"
  export LANEKEEP_CONFIG_HASH_FILE="$TEST_TMP/.lanekeep/config_hash"
  # Env var has wrong hash — empty file falls through, env var mismatch denies
  export LANEKEEP_CONFIG_HASH="bad0000000000000000000000000000000000000000000000000000000000000"
  export LANEKEEP_CONFIG_MTIME="0"
  # Ensure config is newer than hash file so -nt fast-path is not taken
  touch "$LANEKEEP_CONFIG_FILE"
  verify_config_integrity || true
  [ "$INTEGRITY_PASSED" = "false" ]
}

# ── 14. Hash file permissions are 0600 after load_config ──

@test "config integrity: hash file has 0600 permissions after load_config" {
  export PROJECT_DIR="$TEST_TMP"
  load_config "$TEST_TMP"
  local perms
  perms=$(stat -c '%a' "$TEST_TMP/.lanekeep/config_hash")
  [ "$perms" = "600" ]
}
