#!/usr/bin/env bats
# Tests for lanekeep rules command (list, export, import)

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
# lanekeep rules export
# ============================================================================

@test "lanekeep rules export outputs valid JSON" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" export
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.rules | type == "array"' >/dev/null
}

@test "lanekeep rules export --category filters correctly" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" export --category git
  [ "$status" -eq 0 ]
  local count
  count=$(printf '%s' "$output" | jq '[.rules[] | select(.category != "git")] | length')
  [ "$count" -eq 0 ]
  local git_count
  git_count=$(printf '%s' "$output" | jq '.rules | length')
  [ "$git_count" -gt 0 ]
}

# ============================================================================
# lanekeep rules list
# ============================================================================

@test "lanekeep rules list shows all rules with IDs" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" list
  [ "$status" -eq 0 ]
  # Should have many lines (171 rules)
  local line_count
  line_count=$(printf '%s\n' "$output" | wc -l)
  [ "$line_count" -gt 100 ]
}

@test "lanekeep rules list --category filters correctly" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" list --category git
  [ "$status" -eq 0 ]
  local line_count
  line_count=$(printf '%s\n' "$output" | wc -l)
  [ "$line_count" -gt 0 ]
  [ "$line_count" -lt 50 ]
}

# ============================================================================
# lanekeep rules import
# ============================================================================

@test "lanekeep rules import adds to extra_rules" {
  # Create import file
  cat > "$TEST_TMP/import.json" <<'EOF'
{
  "rules": [
    {"match": {"command": "custom-cmd"}, "decision": "deny", "reason": "custom", "category": "custom"}
  ]
}
EOF

  # No lanekeep.json exists yet — should create layered config
  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/import.json"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/lanekeep.json" ]

  local extends
  extends=$(jq -r '.extends' "$TEST_TMP/lanekeep.json")
  [ "$extends" = "defaults" ]

  local extra_count
  extra_count=$(jq '.extra_rules | length' "$TEST_TMP/lanekeep.json")
  [ "$extra_count" -eq 1 ]
}

@test "lanekeep rules import appends to existing extra_rules" {
  # Create initial config
  cat > "$TEST_TMP/lanekeep.json" <<'EOF'
{"extends": "defaults", "extra_rules": [{"match": {"command": "old"}, "decision": "deny", "reason": "old", "category": "old"}]}
EOF

  # Import more
  cat > "$TEST_TMP/import.json" <<'EOF'
{"rules": [{"match": {"command": "new"}, "decision": "deny", "reason": "new", "category": "new"}]}
EOF

  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/import.json"
  [ "$status" -eq 0 ]

  local extra_count
  extra_count=$(jq '.extra_rules | length' "$TEST_TMP/lanekeep.json")
  [ "$extra_count" -eq 2 ]
}

@test "lanekeep rules import rejects invalid rule format" {
  cat > "$TEST_TMP/bad.json" <<'EOF'
{"rules": [{"foo": "bar"}]}
EOF

  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/bad.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required fields"* ]]
}

@test "lanekeep rules import rejects rules without reason" {
  cat > "$TEST_TMP/no-reason.json" <<'EOF'
{"rules": [{"match": {"command": "rm"}, "decision": "deny"}]}
EOF
  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/no-reason.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required fields"* ]]
}

@test "lanekeep rules import rejects non-array format" {
  cat > "$TEST_TMP/bad2.json" <<'EOF'
{"rules": "not an array"}
EOF

  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/bad2.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid format"* ]]
}

@test "lanekeep rules import rejects missing file" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/nonexistent.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# ============================================================================
# lanekeep rules roundtrip (export → import)
# ============================================================================

@test "lanekeep rules export/import roundtrip preserves rules" {
  # Export git rules
  "$LANEKEEP_DIR/bin/lanekeep-rules" export --category git > "$TEST_TMP/git-rules.json"

  # Import into a fresh project
  "$LANEKEEP_DIR/bin/lanekeep-rules" import "$TEST_TMP/git-rules.json"

  local imported_count
  imported_count=$(jq '.extra_rules | length' "$TEST_TMP/lanekeep.json")
  local exported_count
  exported_count=$(jq '.rules | length' "$TEST_TMP/git-rules.json")

  [ "$imported_count" -eq "$exported_count" ]
  [ "$imported_count" -gt 0 ]
}

# ============================================================================
# CLI access
# ============================================================================

@test "lanekeep rules accessible via lanekeep CLI" {
  run "$LANEKEEP_DIR/bin/lanekeep" rules list --category git
  [ "$status" -eq 0 ]
  [[ "$output" == *"git"* ]]
}
