#!/usr/bin/env bats
# Tests for bin/lanekeep-audit-settings.
# Verifies the severity classifier on a set of representative entries and
# checks the CLI's exit codes and JSON output shape.

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$PROJECT_DIR/.claude"
  CLI="$LANEKEEP_DIR/bin/lanekeep-audit-settings"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

_settings() {
  # $1 = filename (relative to .claude/), $@=entries
  local file="$PROJECT_DIR/.claude/$1"
  shift
  local entries_json
  entries_json=$(printf '%s\n' "$@" | jq -Rs 'split("\n") | map(select(length > 0))')
  jq -n --argjson allow "$entries_json" \
    '{permissions:{allow:$allow}}' > "$file"
}

# ── HIGH severity classifications ──

@test "HIGH: unrestricted Bash" {
  _settings settings.json 'Bash(*)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HIGH"* ]]
  [[ "$output" == *"Unrestricted Bash"* ]]
}

@test "HIGH: rm -rf pattern" {
  _settings settings.json 'Bash(rm -rf *)'
  run "$CLI" --project "$PROJECT_DIR"
  [ "$status" -eq 1 ]  # HIGH triggers exit 1 without --no-fail
  [[ "$output" == *"HIGH"* ]]
  [[ "$output" == *"Recursive"* ]]
}

@test "HIGH: sudo pre-approval" {
  _settings settings.json 'Bash(sudo apt install)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"HIGH"* ]]
  [[ "$output" == *"Privilege escalation"* ]]
}

@test "HIGH: chmod 777 pre-approval" {
  _settings settings.json 'Bash(chmod 777 file)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"HIGH"* ]]
}

@test "HIGH: piped remote fetch to shell" {
  _settings settings.json 'Bash(curl https://example.com/install | sh)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"HIGH"* ]]
  [[ "$output" == *"piped into a shell"* ]]
}

@test "HIGH: Write with wildcard" {
  _settings settings.json 'Write(*)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"HIGH"* ]]
  [[ "$output" == *"Unrestricted"* ]]
}

@test "HIGH: dd disk-wipe" {
  _settings settings.json 'Bash(dd if=/dev/zero of=/tmp/wipe)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"HIGH"* ]]
  [[ "$output" == *"Disk-wipe"* ]]
}

@test "HIGH: ~/.ssh read pre-approval" {
  _settings settings.json 'Read(~/.ssh/id_rsa)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"HIGH"* ]]
  [[ "$output" == *"secrets"* ]]
}

# ── MEDIUM severity classifications ──

@test "MEDIUM: curl (no piped exec)" {
  _settings settings.json 'Bash(curl https://api.example.com)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MEDIUM"* ]]
  [[ "$output" == *"Network fetch"* ]]
}

@test "MEDIUM: psql pre-approval" {
  _settings settings.json 'Bash(psql -c SELECT *)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"MEDIUM"* ]]
  [[ "$output" == *"Database CLI"* ]]
}

@test "MEDIUM: git push pre-approval" {
  _settings settings.json 'Bash(git push origin main)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"MEDIUM"* ]]
  [[ "$output" == *"VCS push"* ]]
}

@test "MEDIUM: terraform apply" {
  _settings settings.json 'Bash(terraform apply -auto-approve)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"MEDIUM"* ]]
  [[ "$output" == *"IAC"* ]]
}

@test "MEDIUM: docker run (uncontained)" {
  _settings settings.json 'Bash(docker run alpine)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"MEDIUM"* ]]
  [[ "$output" == *"uncontained"* ]]
}

# ── LOW severity + container exemption ──

@test "LOW: docker exec (container-context exempt)" {
  _settings settings.json 'Bash(docker exec myapp curl attacker.com)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LOW"* ]]
  [[ "$output" == *"Container-context"* ]]
}

@test "LOW: kubectl exec (container-context exempt)" {
  _settings settings.json 'Bash(kubectl exec my-pod -- rm -rf /)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"LOW"* ]]
}

@test "LOW: read-only tools" {
  _settings settings.json 'Read(src/*.py)' 'Grep(TODO)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"LOW"* ]]
  [[ "$output" == *"Read-only"* ]]
}

@test "LOW: git status / log" {
  _settings settings.json 'Bash(git status)' 'Bash(git log --oneline)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"LOW"* ]]
}

@test "LOW: project-scoped Write" {
  _settings settings.json 'Write(src/**)' 'Write(tests/**)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [[ "$output" == *"LOW"* ]]
  [[ "$output" == *"Project-scoped"* ]]
}

# ── Exit codes ──

@test "exit 0 when no HIGH findings" {
  _settings settings.json 'Bash(git status)' 'Bash(curl example.com)'
  run "$CLI" --project "$PROJECT_DIR"
  [ "$status" -eq 0 ]
}

@test "exit 1 when HIGH findings present (no --no-fail)" {
  _settings settings.json 'Bash(rm -rf /)'
  run "$CLI" --project "$PROJECT_DIR"
  [ "$status" -eq 1 ]
}

@test "exit 0 with --no-fail even when HIGH present" {
  _settings settings.json 'Bash(rm -rf /)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [ "$status" -eq 0 ]
}

@test "exit 0 when no settings files found" {
  rm -rf "$PROJECT_DIR/.claude"
  run "$CLI" --project "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No .claude"* ]]
}

@test "exit 2 on malformed JSON settings" {
  echo 'not-json' > "$PROJECT_DIR/.claude/settings.json"
  run "$CLI" --project "$PROJECT_DIR"
  [ "$status" -eq 2 ]
}

# ── JSON output ──

@test "--json emits parseable JSON with summary counts" {
  _settings settings.json 'Bash(rm -rf /)' 'Bash(curl example.com)' 'Bash(git status)'
  run "$CLI" --no-fail --json --project "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  # Must be valid JSON
  echo "$output" | jq . >/dev/null
  # Summary counts
  [ "$(echo "$output" | jq '.summary.high')" = "1" ]
  [ "$(echo "$output" | jq '.summary.medium')" = "1" ]
  [ "$(echo "$output" | jq '.summary.low')" = "1" ]
  [ "$(echo "$output" | jq '.summary.files_scanned')" = "1" ]
}

@test "--json findings carry severity + entry + rationale + file" {
  _settings settings.json 'Bash(rm -rf /)'
  run "$CLI" --no-fail --json --project "$PROJECT_DIR"
  local finding
  finding=$(echo "$output" | jq -r '.findings[0]')
  [ "$(echo "$finding" | jq -r '.severity')" = "HIGH" ]
  [ "$(echo "$finding" | jq -r '.entry')" = "Bash(rm -rf /)" ]
  [[ "$(echo "$finding" | jq -r '.rationale')" == *"Recursive"* ]]
  [[ "$(echo "$finding" | jq -r '.file')" == *"settings.json"* ]]
}

# ── Multi-file scanning ──

@test "scans both settings.json and settings.local.json" {
  _settings settings.json 'Bash(git status)'
  _settings settings.local.json 'Bash(rm -rf /)'
  run "$CLI" --no-fail --json --project "$PROJECT_DIR"
  [ "$(echo "$output" | jq '.summary.files_scanned')" = "2" ]
  [ "$(echo "$output" | jq '.summary.high')" = "1" ]
  [ "$(echo "$output" | jq '.summary.low')" = "1" ]
}

# ── Unclassified fallback ──

@test "INFO: unrecognised pattern falls through" {
  _settings settings.json 'CustomTool(anything)'
  run "$CLI" --no-fail --project "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO"* ]]
  [[ "$output" == *"Unclassified"* ]]
}
