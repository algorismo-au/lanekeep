#!/usr/bin/env bats
# Tests for custom rules DX: add, test, validate, and [custom] label

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ============================================================================
# lanekeep rules validate
# ============================================================================

@test "validate: defaults pass with no errors" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"passed"* ]]
}

@test "validate: detects missing required fields" {
  cat > "$TEST_TMP/bad.json" <<'EOF'
{"rules": [{"decision": "deny", "reason": "no match"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing 'match' field"* ]]
}

@test "validate: detects invalid decision value" {
  cat > "$TEST_TMP/bad.json" <<'EOF'
{"rules": [{"match": {"command": "rm"}, "decision": "block", "reason": "test"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid decision 'block'"* ]]
}

@test "validate: warns on missing id" {
  cat > "$TEST_TMP/noid.json" <<'EOF'
{"rules": [{"match": {"command": "rm"}, "decision": "deny", "reason": "test"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/noid.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing 'id' field"* ]]
}

@test "validate: warns on broad match" {
  cat > "$TEST_TMP/broad.json" <<'EOF'
{"rules": [{"id": "x", "match": {}, "decision": "deny", "reason": "test"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/broad.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"broad match"* ]]
}

@test "validate: warns on single-char command match" {
  cat > "$TEST_TMP/short.json" <<'EOF'
{"rules": [{"id": "x", "match": {"command": "x"}, "decision": "deny", "reason": "test"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/short.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"very short command match"* ]]
}

@test "validate: warns on duplicate IDs" {
  cat > "$TEST_TMP/dup.json" <<'EOF'
{"rules": [
  {"id": "dup-1", "match": {"command": "a"}, "decision": "deny", "reason": "first"},
  {"id": "dup-1", "match": {"command": "b"}, "decision": "deny", "reason": "second"}
]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/dup.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Duplicate id 'dup-1'"* ]]
}

@test "validate: validates extra_rules in layered config" {
  cat > "$TEST_TMP/layered.json" <<'EOF'
{"extends": "defaults", "extra_rules": [
  {"match": {"command": "deploy"}, "decision": "deny", "reason": "blocked"}
]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/layered.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing 'id' field"* ]]
}

@test "validate: clean rules pass" {
  cat > "$TEST_TMP/good.json" <<'EOF'
{"rules": [
  {"id": "r-1", "match": {"command": "deploy"}, "decision": "deny", "reason": "blocked", "category": "custom"}
]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/good.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no issues"* ]]
}

# ============================================================================
# lanekeep rules add
# ============================================================================

@test "add: creates layered config with custom rule" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "deploy --prod" \
    --decision deny \
    --reason "No prod deploys" \
    --category deployment \
    --id "deploy-001"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added rule: deploy-001"* ]]

  # Verify lanekeep.json structure
  [ -f "$TEST_TMP/lanekeep.json" ]
  local extends
  extends=$(jq -r '.extends' "$TEST_TMP/lanekeep.json")
  [ "$extends" = "defaults" ]

  local count
  count=$(jq '.extra_rules | length' "$TEST_TMP/lanekeep.json")
  [ "$count" -eq 1 ]

  local rule_id
  rule_id=$(jq -r '.extra_rules[0].id' "$TEST_TMP/lanekeep.json")
  [ "$rule_id" = "deploy-001" ]
}

@test "add: appends to existing extra_rules" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{"extends": "defaults", "extra_rules": [{"id": "existing", "match": {"command": "old"}, "decision": "deny", "reason": "old"}]}
EOF

  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "new-cmd" \
    --decision ask \
    --reason "Needs approval"
  [ "$status" -eq 0 ]

  local count
  count=$(jq '.extra_rules | length' "$TEST_TMP/lanekeep.json")
  [ "$count" -eq 2 ]
}

@test "add: auto-generates ID when not provided" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "something" \
    --decision deny \
    --reason "Test rule"
  [ "$status" -eq 0 ]

  local rule_id
  rule_id=$(jq -r '.extra_rules[0].id' "$TEST_TMP/lanekeep.json")
  [[ "$rule_id" == custom-* ]]
}

@test "add: defaults category to 'custom'" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "test" \
    --decision deny \
    --reason "Test"
  [ "$status" -eq 0 ]

  local category
  category=$(jq -r '.extra_rules[0].category' "$TEST_TMP/lanekeep.json")
  [ "$category" = "custom" ]
}

@test "add: rejects missing decision" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "test" \
    --reason "Test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--decision is required"* ]]
}

@test "add: rejects invalid decision" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "test" \
    --decision block \
    --reason "Test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid decision"* ]]
}

@test "add: rejects missing match conditions" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --decision deny \
    --reason "No match"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least one match condition"* ]]
}

@test "add: supports --match-tool" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-tool "^Write$" \
    --decision ask \
    --reason "Approve writes" \
    --id "write-ask"
  [ "$status" -eq 0 ]

  local match_tool
  match_tool=$(jq -r '.extra_rules[0].match.tool' "$TEST_TMP/lanekeep.json")
  [ "$match_tool" = "^Write\$" ]
}

@test "add: supports --match-pattern" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-pattern "password" \
    --decision deny \
    --reason "No passwords" \
    --id "no-pw"
  [ "$status" -eq 0 ]

  local match_pat
  match_pat=$(jq -r '.extra_rules[0].match.pattern' "$TEST_TMP/lanekeep.json")
  [ "$match_pat" = "password" ]
}

@test "add: supports multiple match conditions" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "deploy" \
    --match-target "/prod/" \
    --decision deny \
    --reason "No prod deploys"
  [ "$status" -eq 0 ]

  local has_command has_target
  has_command=$(jq 'has("command")' "$TEST_TMP/lanekeep.json" 2>/dev/null || echo "false")
  # Check rule has both match fields
  local cmd tgt
  cmd=$(jq -r '.extra_rules[0].match.command' "$TEST_TMP/lanekeep.json")
  tgt=$(jq -r '.extra_rules[0].match.target' "$TEST_TMP/lanekeep.json")
  [ "$cmd" = "deploy" ]
  [ "$tgt" = "/prod/" ]
}

# ============================================================================
# lanekeep rules test
# ============================================================================

@test "test: matches default deny rule" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" test "rm -rf /"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Result: DENY"* ]]
  [[ "$output" == *"sys-003"* ]]
  [[ "$output" == *"blocked"* ]]
}

@test "test: shows default allow for benign command" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" test "echo hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALLOW"* ]]
  [[ "$output" == *"no rule matched"* ]]
}

@test "test: matches custom rules with [custom] label" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "extends": "defaults",
  "extra_rules": [
    {"id": "my-rule", "match": {"command": "deploy --prod"}, "decision": "deny", "reason": "No prod deploys", "category": "deployment"}
  ]
}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" test "deploy --prod"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DENY"* ]]
  [[ "$output" == *"my-rule"* ]]
  [[ "$output" == *"[custom]"* ]]
  [[ "$output" == *"No prod deploys"* ]]
}

@test "test: supports --tool flag" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" test "some content" --tool Write
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [[ "$output" == *"tool=Write"* ]]
}

@test "test: errors on missing command" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" test
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "test: matches ask rules" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" test "curl https://example.com"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ASK"* ]] || [[ "$output" == *"DENY"* ]]
}

@test "test: respects disabled_rules" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "extends": "defaults",
  "disabled_rules": ["inf-004"]
}
EOF
  # inf-004 matches "aws s3 rm" (cloud deletion deny), but we disabled it
  # Without inf-004, "aws s3 rm" should fall through to inf-014 (cloud CLI ask)
  run "$LANEKEEP_DIR/bin/lanekeep-rules" test "aws s3 rm --recursive"
  [ "$status" -eq 1 ]
  # Should NOT match inf-004 (disabled)
  [[ "$output" != *"inf-004"* ]]
  # Should still be caught by inf-014 (broader cloud CLI rule)
  [[ "$output" == *"inf-014"* ]]
}

# ============================================================================
# [custom] label in eval-rules.sh
# ============================================================================

@test "custom label: extra_rules get source=custom after resolve" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "extends": "defaults",
  "extra_rules": [
    {"id": "my-custom", "match": {"command": "custom-thing"}, "decision": "deny", "reason": "custom"}
  ]
}
EOF

  # Resolve config using config.sh
  mkdir -p "$TEST_TMP/.lanekeep"
  export LANEKEEP_DIR PROJECT_DIR="$TEST_TMP"
  source "$LANEKEEP_DIR/lib/config.sh"
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"

  # Check that custom rule has source=custom
  local source
  source=$(jq -r '.rules[-1].source' "$LANEKEEP_CONFIG_FILE")
  [ "$source" = "custom" ]
}

@test "custom label: default rules have no source field" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "extends": "defaults",
  "extra_rules": [
    {"id": "my-custom", "match": {"command": "custom-thing"}, "decision": "deny", "reason": "custom"}
  ]
}
EOF

  mkdir -p "$TEST_TMP/.lanekeep"
  export LANEKEEP_DIR PROJECT_DIR="$TEST_TMP"
  source "$LANEKEEP_DIR/lib/config.sh"
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"

  # Default rules should not have source field
  local first_source
  first_source=$(jq -r '.rules[0].source // "none"' "$LANEKEEP_CONFIG_FILE")
  [ "$first_source" = "none" ]
}

# ============================================================================
# Integration: add + test roundtrip
# ============================================================================

@test "integration: add rule then test matches it" {
  # Add a custom rule
  "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "internal-deploy" \
    --decision deny \
    --reason "Blocked by policy" \
    --id "int-001"

  # Test that it matches
  run "$LANEKEEP_DIR/bin/lanekeep-rules" test "internal-deploy --target staging"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DENY"* ]]
  [[ "$output" == *"int-001"* ]]
  [[ "$output" == *"[custom]"* ]]
}

@test "integration: add rule then validate passes" {
  "$LANEKEEP_DIR/bin/lanekeep-rules" add \
    --match-command "dangerous-cmd" \
    --decision deny \
    --reason "Not allowed" \
    --id "safe-001" \
    --category security

  run "$LANEKEEP_DIR/bin/lanekeep-rules" validate "$TEST_TMP/lanekeep.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no issues"* ]]
}
