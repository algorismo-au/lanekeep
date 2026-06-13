#!/usr/bin/env bats
# validate_patterns — regex pre-validation at config load.
# Asserts:
#   - invalid regex is flagged
#   - real ReDoS shapes (`(x+)+`, `(x*)*`) are flagged
#   - outer `?` quantifier is NOT flagged (matches at most once — bounded backtracking)
#   - the shipped default config passes validation

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  mkdir -p "$TEST_TMP"
}
teardown() { rm -rf "$TEST_TMP"; return 0; }

@test "validate_patterns: detects invalid regex" {
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
  local config="$TEST_TMP/bad-regex.json"
  cat > "$config" <<'JSON'
{"rules":[{"match":{"pattern":"[invalid"},"decision":"deny","reason":"test"}]}
JSON
  run validate_patterns "$config"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid regex"* ]]
}

@test "validate_patterns: detects nested quantifiers (ReDoS)" {
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
  local config="$TEST_TMP/redos.json"
  cat > "$config" <<'JSON'
{"rules":[{"match":{"pattern":"(a+)+$"},"decision":"deny","reason":"test"}]}
JSON
  run validate_patterns "$config"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nested quantifiers"* ]] || [[ "$output" == *"ReDoS"* ]]
}

@test "validate_patterns: outer ? quantifier is not flagged as ReDoS" {
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
  local config="$TEST_TMP/optional-group.json"
  cat > "$config" <<'JSON'
{"rules":[{"match":{"pattern":"credentials(\\.[a-z0-9_-]+)?$"},"decision":"deny","reason":"test"}]}
JSON
  run validate_patterns "$config"
  [ "$status" -eq 0 ]
}

@test "validate_patterns: default config passes" {
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
  validate_patterns "$LANEKEEP_DIR/defaults/lanekeep.json"
}
