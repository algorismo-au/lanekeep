#!/usr/bin/env bats
# Tests for policies.mcp_inventory: declared-set match + count ceiling.

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  source "$LANEKEEP_DIR/lib/eval-rules.sh"

  TEST_TMP="$(mktemp -d)"
  unset LANEKEEP_TRACE_FILE _CFG_MCP_INVENTORY_ENABLED
}

teardown() {
  rm -rf "$TEST_TMP"
  unset LANEKEEP_TRACE_FILE _CFG_MCP_INVENTORY_ENABLED
  return 0
}

# Seed $TEST_TMP/trace.jsonl with N distinct mcp__* tool_name entries.
seed_trace() {
  local n="$1"
  local path="$TEST_TMP/trace.jsonl"
  : > "$path"
  for i in $(seq 1 "$n"); do
    printf '{"tool_name":"mcp__srv%d__op"}\n' "$i" >> "$path"
  done
  export LANEKEEP_TRACE_FILE="$path"
}

# ── 1. Disabled bypasses declared-list enforcement ──

@test "mcp_inventory: disabled bypasses declared lists" {
  cat > "$TEST_TMP/cfg.json" <<'EOF'
{ "rules": [], "policies": { "mcp_inventory": {
  "enabled": false,
  "declared_servers": ["filesystem"],
  "on_undeclared_server": "deny"
}}}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/cfg.json"
  rules_eval "mcp__stripe__charge" '{}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── 2. Undeclared server triggers configured ask decision ──

@test "mcp_inventory: undeclared server -> ask, reason names server" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/tests/fixtures/lanekeep-mcp-inventory.json"
  rules_eval "mcp__stripe__charge" '{}' || true
  [ "$RULES_PASSED" = "false" ]
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"mcp_inventory"* ]]
  [[ "$RULES_REASON" == *"stripe"* ]]
  [[ "$RULES_HINT" == *"undeclared server"* ]]
}

# ── 3. Undeclared tool triggers configured ask decision ──

@test "mcp_inventory: undeclared tool -> ask" {
  cat > "$TEST_TMP/cfg.json" <<'EOF'
{ "rules": [], "policies": { "mcp_inventory": {
  "enabled": true,
  "declared_tools": ["mcp__filesystem__read_file"],
  "on_undeclared_tool": "ask"
}}}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/cfg.json"
  rules_eval "mcp__filesystem__write_file" '{}' || true
  [ "$RULES_PASSED" = "false" ]
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"declared_tools"* ]]
}

# ── 4. Count under ceiling passes ──

@test "mcp_inventory: count under ceiling passes" {
  cat > "$TEST_TMP/cfg.json" <<'EOF'
{ "rules": [], "policies": { "mcp_inventory": {
  "enabled": true,
  "max_tool_count": 25,
  "on_excess": "warn"
}}}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/cfg.json"
  seed_trace 5
  rules_eval "mcp__filesystem__read_file" '{}' || true
  [ "$RULES_PASSED" = "true" ]
}

# ── 5. Count over ceiling fires on_excess=warn ──

@test "mcp_inventory: count over ceiling -> warn" {
  cat > "$TEST_TMP/cfg.json" <<'EOF'
{ "rules": [], "policies": { "mcp_inventory": {
  "enabled": true,
  "max_tool_count": 25,
  "on_excess": "warn"
}}}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/cfg.json"
  seed_trace 26
  rules_eval "mcp__filesystem__read_file" '{}' || true
  [ "$RULES_PASSED" = "true" ]
  [ "$RULES_DECISION" = "warn" ]
  [[ "$RULES_REASON" == *"WARNING"* ]]
  [[ "$RULES_REASON" == *"mcp_inventory"* ]]
}

# ── 6. Non-MCP tool bypasses all inventory checks ──

@test "mcp_inventory: non-MCP tool bypasses checks" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/tests/fixtures/lanekeep-mcp-inventory.json"
  seed_trace 26
  rules_eval "Bash" '{"command":"ls"}' || true
  [ "$RULES_PASSED" = "true" ]
}
