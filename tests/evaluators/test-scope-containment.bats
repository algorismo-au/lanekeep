#!/usr/bin/env bats
# Tests for lib/eval-scope-containment.sh (Tier 0.6).
# Enforces TaskSpec .allowed_paths on Write/Edit + destructive Bash commands.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/eval-scope-containment.sh"
  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$PROJECT_DIR/src/auth" "$PROJECT_DIR/lib" "$PROJECT_DIR/tests" "$PROJECT_DIR/vendor"
  # Seed allowed_paths via env — mirrors the handler mega-jq path.
  local RS=$'\x1e'
  export _CFG_SCOPE_ENABLED="true"
  export _CFG_SCOPE_DECISION="deny"
  export _CFG_SCOPE_ALLOWED_PATHS="src/${RS}lib/foo.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
  unset _CFG_SCOPE_ENABLED _CFG_SCOPE_DECISION _CFG_SCOPE_ALLOWED_PATHS LANEKEEP_TASKSPEC_FILE
  return 0
}

# ── Opt-in semantics ──

@test "no allowed_paths declared → no-op (opt-in)" {
  export _CFG_SCOPE_ALLOWED_PATHS=""
  scope_containment_eval "Write" '{"file_path":"anywhere.txt"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "disabled evaluator → no-op even with allowed_paths set" {
  export _CFG_SCOPE_ENABLED="false"
  scope_containment_eval "Write" '{"file_path":"/etc/hosts"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "non-Write/Edit/Bash tool → no-op" {
  scope_containment_eval "Read" '{"file_path":"/etc/hosts"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

# ── Write / Edit ──

@test "Write inside allowed_paths (prefix match) → allow" {
  scope_containment_eval "Write" '{"file_path":"src/auth/oidc.py"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "Write on exact allowed_paths file → allow" {
  scope_containment_eval "Write" '{"file_path":"lib/foo.sh"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "Write outside allowed_paths → deny" {
  scope_containment_eval "Write" '{"file_path":"vendor/pkg/main.c"}' || true
  [ "$SCOPE_PASSED" = "false" ]
  [ "$SCOPE_DECISION" = "deny" ]
  [[ "$SCOPE_REASON" == *"vendor/pkg/main.c"* ]]
}

@test "Edit outside allowed_paths → deny" {
  scope_containment_eval "Edit" '{"file_path":"/etc/hosts"}' || true
  [ "$SCOPE_PASSED" = "false" ]
  [ "$SCOPE_DECISION" = "deny" ]
}

@test "Write with absolute path inside allowed → allow" {
  scope_containment_eval "Write" "{\"file_path\":\"$PROJECT_DIR/src/auth/oidc.py\"}" || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "Write with allowed_path being absolute → allow" {
  export _CFG_SCOPE_ALLOWED_PATHS="$PROJECT_DIR/src/"
  scope_containment_eval "Write" '{"file_path":"src/auth/oidc.py"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

# ── Destructive Bash commands ──

@test "Bash: rm inside allowed_paths → allow" {
  scope_containment_eval "Bash" '{"command":"rm src/auth/old.py"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "Bash: rm outside allowed_paths → deny" {
  scope_containment_eval "Bash" '{"command":"rm vendor/pkg/main.c"}' || true
  [ "$SCOPE_PASSED" = "false" ]
  [[ "$SCOPE_REASON" == *"vendor/pkg/main.c"* ]]
}

@test "Bash: rm -rf outside → deny (flag skipping)" {
  scope_containment_eval "Bash" '{"command":"rm -rf /tmp/foo"}' || true
  [ "$SCOPE_PASSED" = "false" ]
}

@test "Bash: rm with multiple targets — any outside blocks" {
  scope_containment_eval "Bash" '{"command":"rm src/foo.py vendor/bar.c"}' || true
  [ "$SCOPE_PASSED" = "false" ]
  [[ "$SCOPE_REASON" == *"vendor/bar.c"* ]]
}

@test "Bash: mv target outside → deny" {
  scope_containment_eval "Bash" '{"command":"mv src/foo.py /etc/foo.py"}' || true
  [ "$SCOPE_PASSED" = "false" ]
}

@test "Bash: truncate outside → deny" {
  scope_containment_eval "Bash" '{"command":"truncate -s 0 /var/log/all.log"}' || true
  [ "$SCOPE_PASSED" = "false" ]
}

@test "Bash: dd outside → deny" {
  scope_containment_eval "Bash" '{"command":"dd if=/dev/zero of=/tmp/wiper bs=1M"}' || true
  [ "$SCOPE_PASSED" = "false" ]
}

@test "Bash: shred outside → deny" {
  scope_containment_eval "Bash" '{"command":"shred -z /etc/passwd"}' || true
  [ "$SCOPE_PASSED" = "false" ]
}

@test "Bash: unlink outside → deny" {
  scope_containment_eval "Bash" '{"command":"unlink /etc/hosts"}' || true
  [ "$SCOPE_PASSED" = "false" ]
}

# ── find … -delete / -exec rm ──

@test "Bash: find -delete outside → deny" {
  scope_containment_eval "Bash" '{"command":"find /tmp/junk -name *.log -delete"}' || true
  [ "$SCOPE_PASSED" = "false" ]
  [[ "$SCOPE_REASON" == *"/tmp/junk"* ]]
}

@test "Bash: find -delete inside → allow" {
  scope_containment_eval "Bash" '{"command":"find src -name *.pyc -delete"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "Bash: find -exec rm outside → deny" {
  scope_containment_eval "Bash" '{"command":"find /var/cache -type f -exec rm {} +"}' || true
  [ "$SCOPE_PASSED" = "false" ]
}

# ── Non-destructive commands — no-op ──

@test "Bash: ls (non-destructive) → allow anywhere" {
  scope_containment_eval "Bash" '{"command":"ls /etc"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "Bash: cat (non-destructive) → allow anywhere" {
  scope_containment_eval "Bash" '{"command":"cat /etc/hosts"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "Bash: git status → allow" {
  scope_containment_eval "Bash" '{"command":"git status"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "Bash: mkdir → allow (not in destructive list)" {
  scope_containment_eval "Bash" '{"command":"mkdir /tmp/foo"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

# ── Decision override ──

@test "custom decision=ask honoured" {
  export _CFG_SCOPE_DECISION="ask"
  scope_containment_eval "Write" '{"file_path":"/etc/hosts"}' || true
  [ "$SCOPE_DECISION" = "ask" ]
  [[ "$SCOPE_REASON" == *"APPROVAL NEEDED"* ]]
}

@test "custom decision=warn honoured" {
  export _CFG_SCOPE_DECISION="warn"
  scope_containment_eval "Write" '{"file_path":"/etc/hosts"}' || true
  [ "$SCOPE_DECISION" = "warn" ]
}

# ── TaskSpec loading (fallback path) ──

@test "TaskSpec .allowed_paths read from LANEKEEP_TASKSPEC_FILE when _CFG_ unset" {
  local ts="$TEST_TMP/taskspec.json"
  printf '{"allowed_paths":["src/","docs/"]}' > "$ts"
  export LANEKEEP_TASKSPEC_FILE="$ts"
  unset _CFG_SCOPE_ALLOWED_PATHS

  # Inside → allow
  scope_containment_eval "Write" '{"file_path":"src/x.py"}' || true
  [ "$SCOPE_PASSED" = "true" ]

  # Outside → deny
  scope_containment_eval "Write" '{"file_path":"vendor/y.py"}' || true
  [ "$SCOPE_PASSED" = "false" ]
}

@test "empty TaskSpec.allowed_paths → no-op" {
  local ts="$TEST_TMP/taskspec.json"
  printf '{"allowed_paths":[]}' > "$ts"
  export LANEKEEP_TASKSPEC_FILE="$ts"
  unset _CFG_SCOPE_ALLOWED_PATHS

  scope_containment_eval "Write" '{"file_path":"vendor/y.py"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

@test "missing TaskSpec file → no-op" {
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/does-not-exist.json"
  unset _CFG_SCOPE_ALLOWED_PATHS

  scope_containment_eval "Write" '{"file_path":"vendor/y.py"}' || true
  [ "$SCOPE_PASSED" = "true" ]
}

# ── Path-traversal defence ──

@test "Path traversal (../etc) → normalises and still denies out-of-scope" {
  # allowed_paths = src/ ; target = ../etc/hosts (relative)
  scope_containment_eval "Write" '{"file_path":"src/../etc/hosts"}' || true
  # Normalisation preserves the literal path for the trace; matched=false
  # because the resolved path is not under src/.
  [ "$SCOPE_PASSED" = "false" ]
}
