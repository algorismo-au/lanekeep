#!/usr/bin/env bats
# Tests for full installation opacity — sec-041 through sec-045.
# Ensures the governed agent cannot read lanekeep source, config, docs,
# env vars, or discover the binary location.

load ../test_helper

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_TASKSPEC_FILE=""
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test-session.jsonl"
  export LANEKEEP_SESSION_ID="test-session"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"input_token_count":0,"output_token_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
}
teardown() { rm -rf "$TEST_TMP"; return 0; }

# ============================================================================
# sec-041: Read/Glob/Grep blocked on installation directories
# ============================================================================

@test "sec-041: Read of lanekeep/lib/eval-rules.sh denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/lib/eval-rules.sh"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/bin/lanekeep-handler denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/opt/lanekeep/bin/lanekeep-handler"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/hooks/evaluate.sh denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/hooks/evaluate.sh"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/defaults/lanekeep.json denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/defaults/lanekeep.json"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Glob of lanekeep/lib/ denied" {
  _isolate_rules "sec-041"
  rules_eval "Glob" '{"pattern":"**/*.sh","path":"/home/user/lanekeep/lib/"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Grep of lanekeep/hooks/ denied" {
  _isolate_rules "sec-041"
  rules_eval "Grep" '{"pattern":"function","path":"/home/user/lanekeep/hooks/"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/ee/README.md denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/ee/README.md"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/ui/server.py denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/ui/server.py"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/keys/pack-signing.pub denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/keys/pack-signing.pub"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/data/pricing.json denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/data/pricing.json"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/plugins.d/examples/docker-safety denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/plugins.d/examples/docker-safety"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of lanekeep/scripts/benchmark.sh denied" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/scripts/benchmark.sh"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-041: Read of unrelated src/lib/utils.ts allowed" {
  _isolate_rules "sec-041"
  rules_eval "Read" '{"file_path":"/home/user/project/src/lib/utils.ts"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "sec-041: Bash not blocked by sec-041 (tool filter)" {
  _isolate_rules "sec-041"
  rules_eval "Bash" '{"command":"echo hello from lanekeep/lib/"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# sec-042: Shell commands reading installation files
# ============================================================================

@test "sec-042: cat lanekeep/lib/eval-rules.sh denied" {
  _isolate_rules "sec-042"
  rules_eval "Bash" '{"command":"cat lanekeep/lib/eval-rules.sh"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-042: ls lanekeep/bin/ denied" {
  _isolate_rules "sec-042"
  rules_eval "Bash" '{"command":"ls lanekeep/bin/"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-042: find lanekeep/hooks/ denied" {
  _isolate_rules "sec-042"
  rules_eval "Bash" '{"command":"find lanekeep/hooks/ -name *.sh"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-042: tree lanekeep/plugins.d/ denied" {
  _isolate_rules "sec-042"
  rules_eval "Bash" '{"command":"tree lanekeep/plugins.d/examples/"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-042: jq lanekeep/defaults/lanekeep.json denied" {
  _isolate_rules "sec-042"
  rules_eval "Bash" '{"command":"jq .version lanekeep/defaults/lanekeep.json"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-042: strings lanekeep/bin/lanekeep denied" {
  _isolate_rules "sec-042"
  rules_eval "Bash" '{"command":"strings /opt/lanekeep/bin/lanekeep"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-042: cat regular-file.sh allowed" {
  _isolate_rules "sec-042"
  rules_eval "Bash" '{"command":"cat src/regular-file.sh"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# sec-043: Env var and process inspection
# ============================================================================

@test "sec-043: echo \$LANEKEEP_DIR denied" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"echo $LANEKEEP_DIR"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-043: echo \${LANEKEEP_DIR} denied" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"echo ${LANEKEEP_DIR}/lib"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-043: printenv LANEKEEP_DIR denied" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"printenv LANEKEEP_DIR"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-043: echo \$LANEKEEP_SOCKET denied" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"echo $LANEKEEP_SOCKET"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-043: echo \$LANEKEEP_CONFIG_FILE denied" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"cat $LANEKEEP_CONFIG_FILE"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-043: ps aux | grep lanekeep denied" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"ps aux | grep lanekeep"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-043: /proc inspection for lanekeep denied" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"cat /proc/1234/cmdline | strings | grep lanekeep"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-043: echo \$HOME allowed (no LANEKEEP ref)" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"echo $HOME"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "sec-043: env NODE_ENV=test npm test allowed" {
  _isolate_rules "sec-043"
  rules_eval "Bash" '{"command":"env NODE_ENV=test npm test"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# sec-044: Binary introspection
# ============================================================================

@test "sec-044: which lanekeep denied" {
  _isolate_rules "sec-044"
  rules_eval "Bash" '{"command":"which lanekeep"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-044: which lanekeep-handler denied" {
  _isolate_rules "sec-044"
  rules_eval "Bash" '{"command":"which lanekeep-handler"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-044: type -a lanekeep denied" {
  _isolate_rules "sec-044"
  rules_eval "Bash" '{"command":"type -a lanekeep"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-044: command -v lanekeep denied" {
  _isolate_rules "sec-044"
  rules_eval "Bash" '{"command":"command -v lanekeep"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-044: whereis lanekeep denied" {
  _isolate_rules "sec-044"
  rules_eval "Bash" '{"command":"whereis lanekeep"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-044: readlink -f /usr/bin/lanekeep denied" {
  _isolate_rules "sec-044"
  rules_eval "Bash" '{"command":"readlink -f /usr/bin/lanekeep"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-044: which npm allowed (not lanekeep)" {
  _isolate_rules "sec-044"
  rules_eval "Bash" '{"command":"which npm"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "sec-044: type -t node allowed (not lanekeep)" {
  _isolate_rules "sec-044"
  rules_eval "Bash" '{"command":"type -t node"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# sec-045: Documentation within installation
# ============================================================================

@test "sec-045: Read lanekeep/README.md denied" {
  _isolate_rules "sec-045"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/README.md"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-045: Read lanekeep/CLAUDE.md denied" {
  _isolate_rules "sec-045"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/CLAUDE.md"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-045: Read lanekeep/REFERENCE.md denied" {
  _isolate_rules "sec-045"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/REFERENCE.md"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-045: Read lanekeep/SECURITY.md denied" {
  _isolate_rules "sec-045"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/SECURITY.md"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-045: Read lanekeep/CONTRIBUTING.md denied" {
  _isolate_rules "sec-045"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/CONTRIBUTING.md"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-045: Read lanekeep/LICENSE denied" {
  _isolate_rules "sec-045"
  rules_eval "Read" '{"file_path":"/home/user/lanekeep/LICENSE"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-045: Grep across lanekeep/REFERENCE denied" {
  _isolate_rules "sec-045"
  rules_eval "Grep" '{"pattern":"evaluator","path":"/home/user/lanekeep/REFERENCE.md"}' || true
  [ "$RULES_DECISION" = "deny" ]
}

@test "sec-045: Read project-level README.md allowed" {
  _isolate_rules "sec-045"
  rules_eval "Read" '{"file_path":"/home/user/project/README.md"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "sec-045: Bash not blocked by sec-045 (tool filter)" {
  _isolate_rules "sec-045"
  rules_eval "Bash" '{"command":"echo lanekeep/README.md"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# governance_paths: Write/Edit/Read protection
# ============================================================================

@test "governance_paths: Write to lanekeep/ee/lib/feature.sh denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"lanekeep/ee/lib/feature.sh","content":"x"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: Write to lanekeep/ui/index.html denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"lanekeep/ui/index.html","content":"x"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: Write to lanekeep/keys/new-key.pub denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"lanekeep/keys/new-key.pub","content":"x"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: Write to lanekeep/data/pricing.json denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"lanekeep/data/pricing.json","content":"x"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: Write to lanekeep/scripts/release.sh denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"lanekeep/scripts/release.sh","content":"x"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: Write to src/app.js allowed (not lanekeep)" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Write" '{"file_path":"src/app.js","content":"x"}'
  [ "$RULES_PASSED" = "true" ]
}

@test "governance_paths: Read of lanekeep/lib/eval-rules.sh denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Read" '{"file_path":"lanekeep/lib/eval-rules.sh"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: Read of lanekeep/hooks/evaluate.sh denied" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Read" '{"file_path":"lanekeep/hooks/evaluate.sh"}' || true
  [ "$RULES_PASSED" = "false" ]
  [[ "$RULES_REASON" == *"governance_paths"* ]]
}

@test "governance_paths: Read of src/app.js allowed (not lanekeep)" {
  export LANEKEEP_CONFIG_FILE="$LANEKEEP_DIR/defaults/lanekeep.json"
  rules_eval "Read" '{"file_path":"src/app.js"}'
  [ "$RULES_PASSED" = "true" ]
}
