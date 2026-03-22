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

@test "extra_rules appends to rule list" {
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
  # Last rule should be the custom one
  local last_reason
  last_reason=$(jq -r '.rules[-1].reason' "$LANEKEEP_CONFIG_FILE")
  [ "$last_reason" = "custom rule" ]
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
