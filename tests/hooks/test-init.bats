#!/usr/bin/env bats
# Tests for lanekeep-init

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  PROJECT_DIR="$TEST_TMP/project"
  mkdir -p "$PROJECT_DIR"
  # Use isolated HOME for TLS tests to avoid polluting real ~/.lanekeep
  export REAL_HOME="$HOME"
  export HOME="$TEST_TMP/fakehome"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

@test "lanekeep-init: creates lanekeep.json from defaults" {
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  [ -f "$PROJECT_DIR/lanekeep.json" ]
  jq -e '.hard_blocks' "$PROJECT_DIR/lanekeep.json" >/dev/null
}

@test "lanekeep-init: skips lanekeep.json if already exists" {
  echo '{"custom":true}' > "$PROJECT_DIR/lanekeep.json"
  result=$("$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR")
  [[ "$result" == *"skipped"* ]]
  # Should not overwrite
  jq -e '.custom' "$PROJECT_DIR/lanekeep.json" >/dev/null
}

@test "lanekeep-init: creates .lanekeep directories" {
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  [ -d "$PROJECT_DIR/.lanekeep" ]
  [ -d "$PROJECT_DIR/.lanekeep/traces" ]
}

@test "lanekeep-init: creates settings.local.json with hook" {
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  [ -f "$PROJECT_DIR/.claude/settings.local.json" ]
  jq -e '.hooks.PreToolUse' "$PROJECT_DIR/.claude/settings.local.json" >/dev/null
}

@test "lanekeep-init: hook has correct nested structure" {
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  settings="$PROJECT_DIR/.claude/settings.local.json"
  # Nested format: .hooks.PreToolUse[0].hooks[0].type
  type=$(jq -r '.hooks.PreToolUse[0].hooks[0].type' "$settings")
  [ "$type" = "command" ]
  cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$settings")
  [[ "$cmd" == *"evaluate.sh" ]]
  timeout=$(jq '.hooks.PreToolUse[0].hooks[0].timeout' "$settings")
  [ "$timeout" -eq 10000 ]
  matcher=$(jq -r '.hooks.PreToolUse[0].matcher' "$settings")
  [ "$matcher" = "" ]
}

@test "lanekeep-init: idempotent — second run skips hook install" {
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  result=$("$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR")
  [[ "$result" == *"skipped"* ]]
  # Should still have exactly one hook entry
  count=$(jq '.hooks.PreToolUse | length' "$PROJECT_DIR/.claude/settings.local.json")
  [ "$count" -eq 1 ]
}

@test "lanekeep-init: merges hook into existing settings" {
  mkdir -p "$PROJECT_DIR/.claude"
  echo '{"other_setting": true}' > "$PROJECT_DIR/.claude/settings.local.json"
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  # Should preserve existing settings
  jq -e '.other_setting' "$PROJECT_DIR/.claude/settings.local.json" >/dev/null
  # And add hook
  jq -e '.hooks.PreToolUse' "$PROJECT_DIR/.claude/settings.local.json" >/dev/null
}

@test "lanekeep-init: prints next steps" {
  result=$("$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR")
  [[ "$result" == *"Next steps"* ]]
  [[ "$result" == *"lanekeep start"* ]]
}

@test "lanekeep-init: installs all hook types (PreToolUse, PostToolUse, Stop)" {
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  settings="$PROJECT_DIR/.claude/settings.local.json"
  jq -e '.hooks.PreToolUse'  "$settings" >/dev/null
  jq -e '.hooks.PostToolUse' "$settings" >/dev/null
  jq -e '.hooks.Stop'        "$settings" >/dev/null
}

@test "lanekeep-init: flat-format hooks get repaired on re-run" {
  mkdir -p "$PROJECT_DIR/.claude"
  # Write flat-format hooks (old schema)
  cat > "$PROJECT_DIR/.claude/settings.local.json" <<'FLAT'
{"hooks":{"PreToolUse":[{"type":"command","command":"/path/to/evaluate.sh","timeout":10000}]}}
FLAT
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  settings="$PROJECT_DIR/.claude/settings.local.json"
  # Should now be nested format
  type=$(jq -r '.hooks.PreToolUse[0].hooks[0].type' "$settings")
  [ "$type" = "command" ]
  # Flat fields should not be at top level of entry
  has_flat=$(jq '.hooks.PreToolUse[0] | has("type")' "$settings")
  [ "$has_flat" = "false" ]
}

@test "lanekeep-init: normalization is idempotent" {
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  settings="$PROJECT_DIR/.claude/settings.local.json"
  before=$(cat "$settings")
  # Source hooks.sh and run normalize again
  source "$LANEKEEP_DIR/lib/hooks.sh"
  normalize_hook_format "$settings" || true
  after=$(cat "$settings")
  [ "$before" = "$after" ]
}

@test "lanekeep-init: mixed flat+nested gets repaired" {
  mkdir -p "$PROJECT_DIR/.claude"
  # One flat (PreToolUse) and one nested (PostToolUse)
  cat > "$PROJECT_DIR/.claude/settings.local.json" <<'MIXED'
{"hooks":{"PreToolUse":[{"type":"command","command":"/path/to/evaluate.sh","timeout":10000}],"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"/path/to/post-evaluate.sh","timeout":10000}]}]}}
MIXED
  source "$LANEKEEP_DIR/lib/hooks.sh"
  normalize_hook_format "$PROJECT_DIR/.claude/settings.local.json"
  settings="$PROJECT_DIR/.claude/settings.local.json"
  # PreToolUse should now be nested
  pre_type=$(jq -r '.hooks.PreToolUse[0].hooks[0].type' "$settings")
  [ "$pre_type" = "command" ]
  # PostToolUse should remain nested (untouched)
  post_type=$(jq -r '.hooks.PostToolUse[0].hooks[0].type' "$settings")
  [ "$post_type" = "command" ]
}

# --- TLS tests ---

@test "lanekeep-init --tls: generates cert and sets ui.tls in lanekeep.json" {
  "$LANEKEEP_DIR/bin/lanekeep-init" --tls "$PROJECT_DIR"
  # Cert files should exist
  [ -f "$HOME/.lanekeep/tls/cert.pem" ]
  [ -f "$HOME/.lanekeep/tls/key.pem" ]
  # Key should be mode 600
  perms=$(stat -c '%a' "$HOME/.lanekeep/tls/key.pem" 2>/dev/null || stat -f '%Lp' "$HOME/.lanekeep/tls/key.pem")
  [ "$perms" = "600" ]
  # lanekeep.json should have ui.tls=true
  jq -e '.ui.tls == true' "$PROJECT_DIR/lanekeep.json" >/dev/null
}

@test "lanekeep-init --tls: reuses existing cert" {
  # First init generates cert
  "$LANEKEEP_DIR/bin/lanekeep-init" --tls "$PROJECT_DIR"
  first_hash=$(sha256sum "$HOME/.lanekeep/tls/cert.pem" | cut -d' ' -f1)
  # Second init reuses
  rm -rf "$PROJECT_DIR"
  mkdir -p "$PROJECT_DIR"
  result=$("$LANEKEEP_DIR/bin/lanekeep-init" --tls "$PROJECT_DIR")
  [[ "$result" == *"reusing"* ]]
  second_hash=$(sha256sum "$HOME/.lanekeep/tls/cert.pem" | cut -d' ' -f1)
  [ "$first_hash" = "$second_hash" ]
}

@test "lanekeep-init: without --tls does not add ui section" {
  "$LANEKEEP_DIR/bin/lanekeep-init" "$PROJECT_DIR"
  # Should NOT have ui key
  result=$(jq 'has("ui")' "$PROJECT_DIR/lanekeep.json")
  [ "$result" = "false" ]
}

@test "lanekeep-init --tls: preserves existing lanekeep.json fields" {
  echo '{"custom_field": "keep_me", "rules": []}' > "$PROJECT_DIR/lanekeep.json"
  "$LANEKEEP_DIR/bin/lanekeep-init" --tls "$PROJECT_DIR"
  # Custom field preserved
  jq -e '.custom_field == "keep_me"' "$PROJECT_DIR/lanekeep.json" >/dev/null
  # Rules preserved
  jq -e '.rules' "$PROJECT_DIR/lanekeep.json" >/dev/null
  # TLS added
  jq -e '.ui.tls == true' "$PROJECT_DIR/lanekeep.json" >/dev/null
}
