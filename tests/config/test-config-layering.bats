#!/usr/bin/env bats
# Tests for config layering: extends, rule_overrides, extra_rules, disabled_rules

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  export LANEKEEP_FAIL_POLICY="allow"
  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP"
  export LANEKEEP_TASKSPEC_FILE=""
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  source "$LANEKEEP_DIR/lib/config.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ============================================================================
# extends: defaults
# ============================================================================

@test "extends defaults merges correctly" {
  # User config overrides one budget value
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "extends": "defaults",
  "budget": {"max_actions": 42}
}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  # Should have rules from defaults
  local rule_count
  rule_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$rule_count" -gt 100 ]
  # Should have overridden budget
  local max_actions
  max_actions=$(jq '.budget.max_actions' "$LANEKEEP_CONFIG_FILE")
  [ "$max_actions" -eq 42 ]
}

@test "rule_overrides patches by ID" {
  # Find a non-locked, non-sys rule we can override
  local first_id
  first_id=$(jq -r '[.rules[] | select(.id | test("^sys-") | not) | select(.locked == true | not) | .id][0] // empty' "$LANEKEEP_DIR/defaults/lanekeep.json")
  if [ -z "$first_id" ]; then
    skip "defaults don't have overridable rule IDs"
  fi

  cat > "$TEST_TMP/lanekeep.json" <<EOF
{
  "extends": "defaults",
  "rule_overrides": [
    {"id": "$first_id", "decision": "ask"}
  ]
}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  local decision
  decision=$(jq -r --arg id "$first_id" '.rules[] | select(.id == $id) | .decision' "$LANEKEEP_CONFIG_FILE")
  [ "$decision" = "ask" ]
}

@test "extra_rules prepends to rule list (1.1: user rules win first-match)" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "extends": "defaults",
  "extra_rules": [
    {"match": {"command": "custom-cmd"}, "decision": "deny", "reason": "custom rule", "category": "custom"}
  ]
}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  local default_count
  default_count=$(jq '.rules | length' "$LANEKEEP_DIR/defaults/lanekeep.json")
  local resolved_count
  resolved_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$resolved_count" -eq $((default_count + 1)) ]
  # First rule should be the custom one (prepended for first-match precedence)
  local first_reason
  first_reason=$(jq -r '.rules[0].reason' "$LANEKEEP_CONFIG_FILE")
  [ "$first_reason" = "custom rule" ]
}

@test "disabled_rules removes from evaluation" {
  # Find a non-locked, non-sys rule we can disable
  local first_id
  first_id=$(jq -r '[.rules[] | select(.id | test("^sys-") | not) | select(.locked == true | not) | .id][0] // empty' "$LANEKEEP_DIR/defaults/lanekeep.json")
  if [ -z "$first_id" ]; then
    skip "defaults don't have disablable rule IDs"
  fi

  cat > "$TEST_TMP/lanekeep.json" <<EOF
{
  "extends": "defaults",
  "disabled_rules": ["$first_id"]
}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  local default_count
  default_count=$(jq '.rules | length' "$LANEKEEP_DIR/defaults/lanekeep.json")
  local resolved_count
  resolved_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$resolved_count" -eq $((default_count - 1)) ]
  # Disabled rule should not appear
  local found
  found=$(jq --arg id "$first_id" '[.rules[] | select(.id == $id)] | length' "$LANEKEEP_CONFIG_FILE")
  [ "$found" -eq 0 ]
}

@test "legacy config without extends still works" {
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$TEST_TMP/lanekeep.json"
  LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  # Config file should still be the user's file (not resolved)
  [ "$LANEKEEP_CONFIG_FILE" = "$TEST_TMP/lanekeep.json" ]
}

@test "new defaults rules appear after update" {
  # Simulate: defaults has N rules, user extends with no overrides
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{"extends": "defaults"}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  local default_count
  default_count=$(jq '.rules | length' "$LANEKEEP_DIR/defaults/lanekeep.json")
  local resolved_count
  resolved_count=$(jq '.rules | length' "$LANEKEEP_CONFIG_FILE")
  [ "$resolved_count" -eq "$default_count" ]
}

@test "extends preserves policies from user config" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "extends": "defaults",
  "policies": {
    "extensions": {"default": "deny", "allowed": [".py", ".js"], "denied": []}
  }
}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  local ext_default
  ext_default=$(jq -r '.policies.extensions.default' "$LANEKEEP_CONFIG_FILE")
  [ "$ext_default" = "deny" ]
}

@test "resolved config written to .lanekeep/resolved-config.json" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{"extends": "defaults"}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  [ -f "$TEST_TMP/.lanekeep/resolved-config.json" ]
  # LANEKEEP_CONFIG_FILE should point to resolved
  [[ "$LANEKEEP_CONFIG_FILE" == *"resolved-config.json" ]]
}

@test "extends field removed from resolved config" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{"extends": "defaults"}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  local has_extends
  has_extends=$(jq 'has("extends")' "$LANEKEEP_CONFIG_FILE")
  [ "$has_extends" = "false" ]
}

# ============================================================================
# lanekeep migrate
# ============================================================================

@test "lanekeep migrate generates minimal override" {
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$TEST_TMP/lanekeep.json"
  run "$LANEKEEP_DIR/bin/lanekeep-migrate" "$TEST_TMP"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/lanekeep.json.new" ]
  # Should have extends field
  local extends
  extends=$(jq -r '.extends' "$TEST_TMP/lanekeep.json.new")
  [ "$extends" = "defaults" ]
}

@test "lanekeep migrate is idempotent" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{"extends": "defaults", "budget": {"max_actions": 99}}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-migrate" "$TEST_TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already using layered config"* ]]
}

@test "lanekeep migrate accessible via lanekeep CLI" {
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$TEST_TMP/lanekeep.json"
  run "$LANEKEEP_DIR/bin/lanekeep" migrate "$TEST_TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"extends: defaults"* ]]
}

# ============================================================================
# 1.1: overrides{} block + extra_rules prepend + deprecation warnings
# ============================================================================

@test "overrides block patches a rule's decision" {
  local first_id
  first_id=$(jq -r '[.rules[] | select(.id | test("^sys-") | not) | select(.locked == true | not) | .id][0] // empty' "$LANEKEEP_DIR/defaults/lanekeep.json")
  [ -n "$first_id" ] || skip "defaults don't have overridable rule IDs"

  cat > "$TEST_TMP/lanekeep.json" <<EOF
{"extends": "defaults", "overrides": {"$first_id": {"decision": "ask"}}}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  local decision
  decision=$(jq -r --arg id "$first_id" '.rules[] | select(.id == $id) | .decision' "$LANEKEEP_CONFIG_FILE")
  [ "$decision" = "ask" ]
}

@test "overrides block disables a rule" {
  local first_id
  first_id=$(jq -r '[.rules[] | select(.id | test("^sys-") | not) | select(.locked == true | not) | .id][0] // empty' "$LANEKEEP_DIR/defaults/lanekeep.json")
  [ -n "$first_id" ] || skip "defaults don't have disableable rule IDs"

  cat > "$TEST_TMP/lanekeep.json" <<EOF
{"extends": "defaults", "overrides": {"$first_id": {"disabled": true}}}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  local present
  present=$(jq -r --arg id "$first_id" '[.rules[] | select(.id == $id)] | length' "$LANEKEEP_CONFIG_FILE")
  [ "$present" = "0" ]
}

@test "overrides on sys-* rule emits WARN block and is ignored" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{"extends": "defaults", "overrides": {"sys-001": {"decision": "allow"}}}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json" 2> "$TEST_TMP/stderr.log"
  local stderr
  stderr=$(cat "$TEST_TMP/stderr.log")
  [[ "$stderr" == *"[lanekeep] WARN:"* ]]
  [[ "$stderr" == *"overrides[\"sys-001\"]"* ]]
  # sys-001 decision should remain unchanged
  local sys001_decision
  sys001_decision=$(jq -r '.rules[] | select(.id == "sys-001") | .decision' "$LANEKEEP_CONFIG_FILE")
  local default_decision
  default_decision=$(jq -r '.rules[] | select(.id == "sys-001") | .decision' "$LANEKEEP_DIR/defaults/lanekeep.json")
  [ "$sys001_decision" = "$default_decision" ]
}

@test "extra_rules fires before defaults (first-match-wins)" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{
  "extends": "defaults",
  "extra_rules": [
    {"match": {"command": "my-custom-tool"}, "decision": "allow", "reason": "user rule"}
  ]
}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json"
  # First rule in resolved order must be the extra_rule
  local first_source
  first_source=$(jq -r '.rules[0].source // empty' "$LANEKEEP_CONFIG_FILE")
  [ "$first_source" = "custom" ]
  local first_reason
  first_reason=$(jq -r '.rules[0].reason' "$LANEKEEP_CONFIG_FILE")
  [ "$first_reason" = "user rule" ]
}

@test "legacy rule_overrides still works + emits DEPRECATED warning" {
  local first_id
  first_id=$(jq -r '[.rules[] | select(.id | test("^sys-") | not) | select(.locked == true | not) | .id][0] // empty' "$LANEKEEP_DIR/defaults/lanekeep.json")
  [ -n "$first_id" ] || skip "defaults don't have overridable rule IDs"

  cat > "$TEST_TMP/lanekeep.json" <<EOF
{"extends": "defaults", "rule_overrides": [{"id": "$first_id", "decision": "ask"}]}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json" 2> "$TEST_TMP/stderr.log"
  local stderr
  stderr=$(cat "$TEST_TMP/stderr.log")
  [[ "$stderr" == *"[lanekeep] DEPRECATED:"* ]]
  local decision
  decision=$(jq -r --arg id "$first_id" '.rules[] | select(.id == $id) | .decision' "$LANEKEEP_CONFIG_FILE")
  [ "$decision" = "ask" ]
}

@test "legacy disabled_rules still works + emits DEPRECATED warning" {
  local first_id
  first_id=$(jq -r '[.rules[] | select(.id | test("^sys-") | not) | select(.locked == true | not) | .id][0] // empty' "$LANEKEEP_DIR/defaults/lanekeep.json")
  [ -n "$first_id" ] || skip "defaults don't have disableable rule IDs"

  cat > "$TEST_TMP/lanekeep.json" <<EOF
{"extends": "defaults", "disabled_rules": ["$first_id"]}
EOF
  resolve_config "$TEST_TMP/lanekeep.json" "$LANEKEEP_DIR/defaults/lanekeep.json" 2> "$TEST_TMP/stderr.log"
  local stderr
  stderr=$(cat "$TEST_TMP/stderr.log")
  [[ "$stderr" == *"[lanekeep] DEPRECATED:"* ]]
  local present
  present=$(jq -r --arg id "$first_id" '[.rules[] | select(.id == $id)] | length' "$LANEKEEP_CONFIG_FILE")
  [ "$present" = "0" ]
}

@test "lanekeep migrate converts rule_overrides to overrides" {
  local first_id
  first_id=$(jq -r '[.rules[] | select(.id | test("^sys-") | not) | select(.locked == true | not) | .id][0] // empty' "$LANEKEEP_DIR/defaults/lanekeep.json")
  [ -n "$first_id" ] || skip "defaults don't have overridable rule IDs"

  cat > "$TEST_TMP/lanekeep.json" <<EOF
{"extends": "defaults", "rule_overrides": [{"id": "$first_id", "decision": "ask", "reason": "loosened"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-migrate" "$TEST_TMP"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/lanekeep.json.new" ]
  local has_overrides has_legacy decision reason
  has_overrides=$(jq 'has("overrides")' "$TEST_TMP/lanekeep.json.new")
  has_legacy=$(jq 'has("rule_overrides")' "$TEST_TMP/lanekeep.json.new")
  decision=$(jq -r --arg id "$first_id" '.overrides[$id].decision' "$TEST_TMP/lanekeep.json.new")
  reason=$(jq -r --arg id "$first_id" '.overrides[$id].reason' "$TEST_TMP/lanekeep.json.new")
  [ "$has_overrides" = "true" ]
  [ "$has_legacy" = "false" ]
  [ "$decision" = "ask" ]
  [ "$reason" = "loosened" ]
}

@test "lanekeep migrate converts disabled_rules to overrides" {
  local first_id
  first_id=$(jq -r '[.rules[] | select(.id | test("^sys-") | not) | select(.locked == true | not) | .id][0] // empty' "$LANEKEEP_DIR/defaults/lanekeep.json")
  [ -n "$first_id" ] || skip "defaults don't have disableable rule IDs"

  cat > "$TEST_TMP/lanekeep.json" <<EOF
{"extends": "defaults", "disabled_rules": ["$first_id"]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-migrate" "$TEST_TMP"
  [ "$status" -eq 0 ]
  local disabled has_legacy
  disabled=$(jq -r --arg id "$first_id" '.overrides[$id].disabled' "$TEST_TMP/lanekeep.json.new")
  has_legacy=$(jq 'has("disabled_rules")' "$TEST_TMP/lanekeep.json.new")
  [ "$disabled" = "true" ]
  [ "$has_legacy" = "false" ]
}

@test "lanekeep migrate is idempotent on overrides-only config" {
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{"extends": "defaults", "overrides": {"sec-001": {"decision": "ask"}}}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-migrate" "$TEST_TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to migrate"* ]]
}
