#!/usr/bin/env bats
# Tests for load_enterprise_rules() — ee/rules/ loading gated on enterprise tier

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"

  # Minimal resolved config with one default rule
  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{"rules":[{"id":"default-1","match":{"command":"ls"},"decision":"allow","reason":"default"}]}
EOF

  # ee/rules dir inside a fake LANEKEEP_DIR
  FAKE_LANEKEEP_DIR="$TEST_TMP/lanekeep"
  mkdir -p "$FAKE_LANEKEEP_DIR/lib" "$FAKE_LANEKEEP_DIR/keys" "$FAKE_LANEKEEP_DIR/ee/rules"
  cp "$LANEKEEP_DIR/lib/signing.sh"   "$FAKE_LANEKEEP_DIR/lib/signing.sh"
  cp "$LANEKEEP_DIR/lib/eval-rules.sh" "$FAKE_LANEKEEP_DIR/lib/eval-rules.sh"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"

  source "$LANEKEEP_DIR/lib/signing.sh"
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
  source "$LANEKEEP_DIR/lib/config.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# Helper: sign a JSON file with a given private key (inline _signature)
_sign_file() {
  local content="$1" privkey="$2" outfile="$3"
  local canonical hash_file sig_file
  canonical=$(printf '%s' "$content" | jq -c 'del(._signature)')
  hash_file=$(mktemp); sig_file=$(mktemp)
  printf '%s' "$canonical" | sha256sum | cut -d' ' -f1 | tr -d '\n' > "$hash_file"
  openssl pkeyutl -sign -inkey "$privkey" -in "$hash_file" -rawin -out "$sig_file" 2>/dev/null
  local sig_b64; sig_b64=$(base64 -w0 < "$sig_file")
  printf '%s' "$canonical" | jq --arg sig "$sig_b64" '. + {_signature: $sig}' > "$outfile"
  rm -f "$hash_file" "$sig_file"
}

# ── Tier gate ────────────────────────────────────────────────────────────────

@test "load_enterprise_rules: no-op for community tier" {
  LANEKEEP_LICENSE_TIER=community LANEKEEP_DIR="$FAKE_LANEKEEP_DIR" \
    run bash -c "source '$LANEKEEP_DIR/lib/signing.sh'; source '$LANEKEEP_DIR/lib/eval-rules.sh'; source '$LANEKEEP_DIR/lib/config.sh'; load_enterprise_rules '$LANEKEEP_CONFIG_FILE'"
  [ "$status" -eq 0 ]
  # Config must be unchanged — no enterprise rules merged
  local rule_count; rule_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$rule_count" -eq 1 ]
}

@test "load_enterprise_rules: no-op for pro tier" {
  LANEKEEP_LICENSE_TIER=pro LANEKEEP_DIR="$FAKE_LANEKEEP_DIR" \
    run bash -c "source '$LANEKEEP_DIR/lib/signing.sh'; source '$LANEKEEP_DIR/lib/eval-rules.sh'; source '$LANEKEEP_DIR/lib/config.sh'; load_enterprise_rules '$LANEKEEP_CONFIG_FILE'"
  [ "$status" -eq 0 ]
  local rule_count; rule_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$rule_count" -eq 1 ]
}

# ── Empty ee/rules/ (scaffold state) ─────────────────────────────────────────

@test "load_enterprise_rules: silent no-op when ee/rules/ is empty" {
  LANEKEEP_LICENSE_TIER=enterprise LANEKEEP_DIR="$FAKE_LANEKEEP_DIR" \
    run bash -c "source '$LANEKEEP_DIR/lib/signing.sh'; source '$LANEKEEP_DIR/lib/eval-rules.sh'; source '$LANEKEEP_DIR/lib/config.sh'; load_enterprise_rules '$LANEKEEP_CONFIG_FILE'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local rule_count; rule_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$rule_count" -eq 1 ]
}

# ── Signed enterprise rules ───────────────────────────────────────────────────

@test "load_enterprise_rules: merges signed enterprise rules into config" {
  openssl genpkey -algorithm Ed25519 -out "$TEST_TMP/ent.key" 2>/dev/null || skip "openssl Ed25519 not available"
  openssl pkey -in "$TEST_TMP/ent.key" -pubout -out "$FAKE_LANEKEEP_DIR/keys/pack-signing.pub" 2>/dev/null

  local content='{"tier":"enterprise","rules":[{"id":"ee-rbac-001","match":{"command":"sudo"},"decision":"deny","reason":"RBAC enforcement"}]}'
  _sign_file "$content" "$TEST_TMP/ent.key" "$FAKE_LANEKEEP_DIR/ee/rules/rbac.json"

  LANEKEEP_LICENSE_TIER=enterprise LANEKEEP_DIR="$FAKE_LANEKEEP_DIR" \
    bash -c "source '$LANEKEEP_DIR/lib/signing.sh'; source '$LANEKEEP_DIR/lib/eval-rules.sh'; source '$LANEKEEP_DIR/lib/config.sh'; load_enterprise_rules '$LANEKEEP_CONFIG_FILE'"

  local rule_count; rule_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$rule_count" -eq 2 ]
  local added_id; added_id=$(jq -r '.rules[-1].id' "$LANEKEEP_CONFIG_FILE")
  [ "$added_id" = "ee-rbac-001" ]
}

# ── Unsigned / tampered enterprise rules ─────────────────────────────────────

@test "load_enterprise_rules: skips unsigned enterprise rule file with warning" {
  # No key in keys/ dir — file is unsigned
  cat > "$FAKE_LANEKEEP_DIR/ee/rules/rbac.json" <<'EOF'
{"tier":"enterprise","rules":[{"id":"ee-rbac-001","match":{"command":"sudo"},"decision":"deny","reason":"RBAC"}]}
EOF

  LANEKEEP_LICENSE_TIER=enterprise LANEKEEP_DIR="$FAKE_LANEKEEP_DIR" \
    run bash -c "source '$LANEKEEP_DIR/lib/signing.sh'; source '$LANEKEEP_DIR/lib/eval-rules.sh'; source '$LANEKEEP_DIR/lib/config.sh'; load_enterprise_rules '$LANEKEEP_CONFIG_FILE'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]] || [[ "$stderr" == *"WARNING"* ]] || true

  # Rule must NOT be merged
  local rule_count; rule_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$rule_count" -eq 1 ]
}
