#!/usr/bin/env bats
# Tests for Pro pack Ed25519 signature verification

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  echo '{}' > "$LANEKEEP_CONFIG_FILE"
  source "$LANEKEEP_DIR/lib/signing.sh"
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# --- Helper: create a signed pack ---
_sign_pack() {
  local canonical="$1"
  local privkey="$2"
  local outfile="$3"

  local hash_file sig_file
  hash_file=$(mktemp)
  sig_file=$(mktemp)
  printf '%s' "$canonical" | sha256sum | cut -d' ' -f1 | tr -d '\n' > "$hash_file"
  openssl pkeyutl -sign -inkey "$privkey" -in "$hash_file" -rawin -out "$sig_file" 2>/dev/null
  local sig_b64
  sig_b64=$(base64 -w0 < "$sig_file")
  printf '%s' "$canonical" | jq --arg sig "$sig_b64" '. + {_signature: $sig}' > "$outfile"
  rm -f "$hash_file" "$sig_file"
}

# --- Free rules ---

@test "free rules load without signature check" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{"rules": [{"id":"test-1","match":{"command":"ls"},"decision":"allow","reason":"test"}]}
EOF
  run verify_pack_rules "$TEST_TMP/rules.json"
  [ "$status" -eq 0 ]
}

@test "community tier loads without signature check" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{"tier":"community","rules": [{"id":"test-1","match":{"command":"ls"},"decision":"allow","reason":"test"}]}
EOF
  run verify_pack_rules "$TEST_TMP/rules.json"
  [ "$status" -eq 0 ]
}

@test "rules without tier field default to free (no signature needed)" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{"rules": [{"id":"r1","match":{"pattern":".*"},"decision":"allow","reason":"ok"}]}
EOF
  run verify_pack_rules "$TEST_TMP/rules.json"
  [ "$status" -eq 0 ]
}

# --- Unsigned Pro packs ---

@test "unsigned pro pack is rejected with exit 2" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{"tier":"pro","rules": [{"id":"soc2-1","match":{"pattern":"password"},"decision":"deny","reason":"SOC2 CC6.1"}]}
EOF
  run verify_pack_rules "$TEST_TMP/rules.json"
  [ "$status" -eq 2 ]
}

@test "unsigned enterprise pack is rejected with exit 2" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{"tier":"enterprise","rules": [{"id":"ent-1","match":{"pattern":".*"},"decision":"deny","reason":"Enterprise only"}]}
EOF
  run verify_pack_rules "$TEST_TMP/rules.json"
  [ "$status" -eq 2 ]
}

# --- Signed Pro packs (Ed25519) ---

@test "valid signed pro pack loads successfully" {
  openssl genpkey -algorithm Ed25519 -out "$TEST_TMP/test.key" 2>/dev/null || skip "openssl Ed25519 not available"
  openssl pkey -in "$TEST_TMP/test.key" -pubout -out "$TEST_TMP/test.pub" 2>/dev/null

  local canonical
  canonical=$(jq -c '.' <<'EOF'
{"tier":"pro","rules":[{"id":"soc2-1","match":{"pattern":"password"},"decision":"deny","reason":"SOC2 CC6.1"}]}
EOF
  )
  _sign_pack "$canonical" "$TEST_TMP/test.key" "$TEST_TMP/rules.json"

  run verify_pack_rules "$TEST_TMP/rules.json" "$TEST_TMP/test.pub"
  [ "$status" -eq 0 ]
}

@test "tampered signed pack is rejected with exit 1" {
  openssl genpkey -algorithm Ed25519 -out "$TEST_TMP/test.key" 2>/dev/null || skip "openssl Ed25519 not available"
  openssl pkey -in "$TEST_TMP/test.key" -pubout -out "$TEST_TMP/test.pub" 2>/dev/null

  local canonical
  canonical=$(jq -c '.' <<'EOF'
{"tier":"pro","rules":[{"id":"soc2-1","match":{"pattern":"password"},"decision":"deny","reason":"SOC2 CC6.1"}]}
EOF
  )
  _sign_pack "$canonical" "$TEST_TMP/test.key" "$TEST_TMP/rules.json"

  # Tamper: change decision from deny to allow
  jq '.rules[0].decision = "allow"' "$TEST_TMP/rules.json" > "$TEST_TMP/tampered.json"

  run verify_pack_rules "$TEST_TMP/tampered.json" "$TEST_TMP/test.pub"
  [ "$status" -eq 1 ]
}

@test "pack signed with wrong key is rejected" {
  openssl genpkey -algorithm Ed25519 -out "$TEST_TMP/sign.key" 2>/dev/null || skip "openssl Ed25519 not available"
  openssl genpkey -algorithm Ed25519 -out "$TEST_TMP/wrong.key" 2>/dev/null
  openssl pkey -in "$TEST_TMP/wrong.key" -pubout -out "$TEST_TMP/wrong.pub" 2>/dev/null

  local canonical
  canonical=$(jq -c '.' <<'EOF'
{"tier":"pro","rules":[{"id":"hipaa-1","match":{"pattern":"PHI"},"decision":"deny","reason":"HIPAA"}]}
EOF
  )
  # Sign with sign.key but verify with wrong.pub
  _sign_pack "$canonical" "$TEST_TMP/sign.key" "$TEST_TMP/rules.json"

  run verify_pack_rules "$TEST_TMP/rules.json" "$TEST_TMP/wrong.pub"
  [ "$status" -eq 1 ]
}

# --- Import integration ---

@test "lanekeep rules import rejects unsigned Pro pack" {
  export PROJECT_DIR="$TEST_TMP"
  cat > "$TEST_TMP/pro-pack.json" <<'EOF'
{"tier":"pro","rules": [{"id":"soc2-1","match":{"pattern":"password"},"decision":"deny","reason":"SOC2 CC6.1"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/pro-pack.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsigned"* ]] || [[ "$output" == *"signing key"* ]]
}

@test "lanekeep rules import accepts free pack without signature" {
  export PROJECT_DIR="$TEST_TMP"
  cat > "$TEST_TMP/free-pack.json" <<'EOF'
{"rules": [{"id":"custom-1","match":{"command":"echo"},"decision":"allow","reason":"test rule"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/free-pack.json"
  [ "$status" -eq 0 ]
}

@test "lanekeep rules import accepts valid signed Pro pack" {
  openssl genpkey -algorithm Ed25519 -out "$TEST_TMP/test.key" 2>/dev/null || skip "openssl Ed25519 not available"
  openssl pkey -in "$TEST_TMP/test.key" -pubout -out "$TEST_TMP/test.pub" 2>/dev/null

  # Configure pubkey path in config
  jq -n --arg pub "$TEST_TMP/test.pub" '{signing: {pubkey_path: $pub}}' > "$LANEKEEP_CONFIG_FILE"

  local canonical
  canonical=$(jq -c '.' <<'EOF'
{"tier":"pro","rules":[{"id":"soc2-1","match":{"pattern":"password"},"decision":"deny","reason":"SOC2"}]}
EOF
  )
  _sign_pack "$canonical" "$TEST_TMP/test.key" "$TEST_TMP/signed-pack.json"

  export PROJECT_DIR="$TEST_TMP"
  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/signed-pack.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"signature verified"* ]]
}

# --- Nonexistent file ---

@test "verify_pack_rules returns 2 for nonexistent file" {
  run verify_pack_rules "$TEST_TMP/nonexistent.json"
  [ "$status" -eq 2 ]
}
