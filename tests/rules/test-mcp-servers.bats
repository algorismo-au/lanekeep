#!/usr/bin/env bats
# Tests for MCP server allowlist/denylist policy

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  source "$LANEKEEP_DIR/lib/eval-rules.sh"

  TEST_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

# ── 1. Denies tool from denied server ──

@test "mcp_servers: denies tool from denied server" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/tests/fixtures/lanekeep-mcp-policies.json"
  rules_eval "mcp__evil__read_file" '{}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"mcp_servers"* ]]
  [[ "$RULES_REASON" == *"evil"* ]]
}

# ── 2. Allows tool from non-denied server ──

@test "mcp_servers: allows tool from non-denied server" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/tests/fixtures/lanekeep-mcp-policies.json"
  rules_eval "mcp__github__list_repos" '{}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── 3. Allows explicitly allowed server ──

@test "mcp_servers: allows explicitly allowed server" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/tests/fixtures/lanekeep-mcp-policies.json"
  rules_eval "mcp__trusted__do_thing" '{}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── 4. default:deny blocks unlisted server ──

@test "mcp_servers: default deny blocks unlisted server" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "mcp_servers": {
      "enabled": true,
      "default": "deny",
      "allowed": ["trusted"],
      "denied": [],
      "type": "free"
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "mcp__unknown__read" '{}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"not in the allowed list"* ]]
}

# ── 5. default:deny allows listed server ──

@test "mcp_servers: default deny allows listed server" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "mcp_servers": {
      "enabled": true,
      "default": "deny",
      "allowed": ["trusted"],
      "denied": [],
      "type": "free"
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "mcp__trusted__read" '{}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── 6. Does not fire on non-MCP tools ──

@test "mcp_servers: does not fire on non-MCP tools" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "mcp_servers": {
      "enabled": true,
      "default": "deny",
      "allowed": [],
      "denied": [],
      "type": "free"
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "Bash" '{"command":"echo hi"}' || true
  [ "$RULES_PASSED" = "true" ]
  rules_eval "Read" '{"file_path":"foo.txt"}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── 7. Denied wins over allowed (symmetric model) ──

@test "mcp_servers: denied wins over allowed" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "mcp_servers": {
      "enabled": true,
      "default": "allow",
      "allowed": ["evil"],
      "denied": ["evil"],
      "type": "free"
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "mcp__evil__read" '{}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"denied list"* ]]
}

# ── 8. Regex pattern matching in denied list ──

@test "mcp_servers: regex pattern matching in denied list" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/tests/fixtures/lanekeep-mcp-policies.json"
  # "rogue.*" pattern should match rogue-server
  rules_eval "mcp__rogue-server__exploit" '{}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"mcp_servers"* ]]
}

# ── 9. Disabled category skips check ──

@test "mcp_servers: disabled category skips check" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "mcp_servers": {
      "enabled": false,
      "default": "deny",
      "allowed": [],
      "denied": ["evil"],
      "type": "free"
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "mcp__evil__read" '{}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── 10. Missing mcp_servers section = no restriction ──

@test "mcp_servers: missing section means no restriction" {
  cat > "$TEST_TMP/rules.json" <<'EOF'
{
  "rules": [],
  "policies": {
    "extensions": {
      "default": "allow",
      "allowed": [],
      "denied": []
    }
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/rules.json"
  rules_eval "mcp__anything__read" '{}' || true
  [ "$RULES_PASSED" = "true" ]
}
