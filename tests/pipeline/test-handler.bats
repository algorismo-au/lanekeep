#!/usr/bin/env bats
# Tests for bin/lanekeep-handler — full evaluation pipeline

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  # Create temp dir for test state/config
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-handler"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  # Copy default config
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"

  # Initialize state with low action count
  printf '{"action_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

@test "Read tool is allowed with default config" {
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "Bash rm -rf is blocked" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /home/user/project"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Tool not in allowlist denied by SchemaEvaluator" {
  # Restrictive taskspec: only Read, Grep, Glob allowed
  cp "$LANEKEEP_DIR/tests/fixtures/taskspec-restrictive.json" "$LANEKEEP_TASKSPEC_FILE"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [ "$decision" = "deny" ]
  [[ "$reason" == *"SchemaEvaluator"* ]]
}

@test "Write with secret denied by RuleEngine" {
  output=$(jq -c '.' "$LANEKEEP_DIR/tests/fixtures/hook-request-write-secret.json" | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [ "$decision" = "deny" ]
  [[ "$reason" == *"RuleEngine"* ]]
}

@test "Budget exceeded denied by BudgetEvaluator" {
  # Set state with count=10, config with max=10
  cp "$LANEKEEP_DIR/tests/fixtures/taskspec-budget.json" "$LANEKEEP_TASKSPEC_FILE"
  printf '{"action_count":10,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [ "$decision" = "deny" ]
  [[ "$reason" == *"BudgetEvaluator"* ]]
}

@test "Malformed JSON input denied" {
  output=$(echo 'not json at all' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [ "$decision" = "deny" ]
  [[ "$reason" == *"Malformed"* ]]
}

@test "Empty stdin denied" {
  output=$(echo '' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [ "$decision" = "deny" ]
  [[ "$reason" == *"Empty"* ]]
}

@test "Bash terraform apply is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"terraform apply -auto-approve"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Bash terraform destroy is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"terraform destroy -auto-approve"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Bash pulumi up is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"pulumi up --yes"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Bash cdk deploy is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"cdk deploy MyStack"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Bash tofu apply is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"tofu apply -auto-approve"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Bash aws s3 rm is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"aws s3 rm s3://my-bucket --recursive"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Bash aws s3 ls is still ask" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"aws s3 ls s3://my-bucket"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "Bash helm uninstall is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"helm uninstall my-release"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Bash dropdb is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"dropdb production_db"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Bash terraform state rm is denied" {
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"terraform state rm aws_instance.web"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

# --- InputPII integration tests ---

@test "Write with SSN triggers InputPII ask decision" {
  output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"data.txt","content":"Employee SSN: 123-45-6789"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [ "$decision" = "ask" ]
  [[ "$reason" == *"InputPII"* ]]
}

@test "Read with SSN in path does NOT trigger InputPII" {
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"ssn-123-45-6789.txt"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "Write with clean content passes InputPII" {
  output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"hello.txt","content":"Hello, world!"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "InputPII on_detect=deny blocks Write with SSN" {
  jq '.evaluators.input_pii.on_detect = "deny"' "$LANEKEEP_CONFIG_FILE" > "$TEST_TMP/tmp.json" && mv "$TEST_TMP/tmp.json" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"data.txt","content":"SSN: 123-45-6789"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [ "$decision" = "deny" ]
  [[ "$reason" == *"InputPII"* ]]
}

@test "InputPII on_detect=warn returns warn decision with SSN" {
  jq '.evaluators.input_pii.on_detect = "warn"' "$LANEKEEP_CONFIG_FILE" > "$TEST_TMP/tmp.json" && mv "$TEST_TMP/tmp.json" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"data.txt","content":"SSN: 123-45-6789"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  warn=$(printf '%s' "$output" | jq -r '.warn // empty')
  [ "$decision" = "warn" ]
  [ -n "$warn" ]
  [[ "$warn" == *"InputPII"* ]]
}

@test "InputPII on_detect=ask returns ask for Write with email" {
  jq '.evaluators.input_pii.on_detect = "ask"' "$LANEKEEP_CONFIG_FILE" > "$TEST_TMP/tmp.json" && mv "$TEST_TMP/tmp.json" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"data.txt","content":"Contact: user@example.com"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "InputPII disabled allows Write with SSN" {
  jq '.evaluators.input_pii.enabled = false' "$LANEKEEP_CONFIG_FILE" > "$TEST_TMP/tmp.json" && mv "$TEST_TMP/tmp.json" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"data.txt","content":"SSN: 123-45-6789"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "InputPII custom patterns detect custom regex" {
  jq '.evaluators.input_pii.pii_patterns = ["EMPLOYEE-[0-9]{6}"]' "$LANEKEEP_CONFIG_FILE" > "$TEST_TMP/tmp.json" && mv "$TEST_TMP/tmp.json" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"data.txt","content":"ID: EMPLOYEE-482901"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "ask" ]
}

@test "InputPII custom patterns do not match default SSN pattern" {
  jq '.evaluators.input_pii.pii_patterns = ["EMPLOYEE-[0-9]{6}"]' "$LANEKEEP_CONFIG_FILE" > "$TEST_TMP/tmp.json" && mv "$TEST_TMP/tmp.json" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"data.txt","content":"SSN: 123-45-6789"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "Rules ask + Schema deny = deny (not ask)" {
  # Restrictive taskspec: Bash not allowed → Schema will deny
  # aws s3 ls triggers rules "ask", but Schema denial must override to "deny"
  cp "$LANEKEEP_DIR/tests/fixtures/taskspec-restrictive.json" "$LANEKEEP_TASKSPEC_FILE"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"aws s3 ls s3://my-bucket"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Rules ask + Budget deny = deny (not ask)" {
  # Budget exceeded: action_count=10, max=10 → Budget will deny
  # aws s3 ls triggers rules "ask", but Budget denial must override to "deny"
  cp "$LANEKEEP_DIR/tests/fixtures/taskspec-budget.json" "$LANEKEEP_TASKSPEC_FILE"
  printf '{"action_count":10,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"aws s3 ls s3://my-bucket"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "deny" ]
}

@test "Multi-line pretty-printed JSON compacted and parsed" {
  # Send raw multi-line JSON — handler must normalize it internally
  output=$(printf '{\n  "tool_name": "Read",\n  "tool_input": {\n    "file_path": "test.txt"\n  }\n}\n' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

# ── Tier 2.1: SessionWriteExecDetector ──────────────────────────────────────

# Seed the trace with a prior Write/Edit entry so the detector has something
# to match against in the current session.
_t21_seed_write() {
  local file_path="$1" tool="${2:-Write}"
  jq -nc \
    --arg tn "$tool" \
    --arg fp "$file_path" \
    '{tool_name:$tn,tool_input:{file_path:$fp},decision:"allow",file_path:$fp}' \
    >> "$LANEKEEP_TRACE_FILE"
}

@test "t2.1: bash cat of session-written .md file is excluded" {
  _t21_seed_write "/tmp/notes.md"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /tmp/notes.md"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [ "$decision" = "allow" ]
  [[ "$warn" != *"Write-then-execute"* ]]
}

@test "t2.1: bash jq of session-written .json file is excluded" {
  _t21_seed_write "/tmp/config.json" "Edit"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"jq .deploy /tmp/config.json"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" != *"Write-then-execute"* ]]
}

@test "t2.1: bash yq of session-written .yaml file is excluded" {
  _t21_seed_write "/tmp/infra.yaml"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"yq .deploy /tmp/infra.yaml"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" != *"Write-then-execute"* ]]
}

@test "t2.1: bash cat of session-written .yml file is excluded" {
  _t21_seed_write "/tmp/values.yml"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /tmp/values.yml"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" != *"Write-then-execute"* ]]
}

@test "t2.1: bash grep of session-written .txt file is excluded" {
  _t21_seed_write "/tmp/data.txt"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"grep foo /tmp/data.txt"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" != *"Write-then-execute"* ]]
}

@test "t2.1: case-insensitive extension match (.MD excluded)" {
  _t21_seed_write "/tmp/README.MD"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /tmp/README.MD"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" != *"Write-then-execute"* ]]
}

@test "t2.1: non-excluded extension surfaces as INFO by default" {
  # Use .bin so we don't collide with sys-032 (/tmp/*) or sys-033 (script-exec regex)
  _t21_seed_write "/home/lk/build/output.bin"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /home/lk/build/output.bin"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" == *"[LaneKeep] INFO"* ]]
  [[ "$warn" == *"Write-then-execute detected (Tier 2.1)"* ]]
  [[ "$warn" != *"[LaneKeep] WARNING"* ]]
}

@test "t2.1: surface_as=warn restores WARNING prefix" {
  _t21_seed_write "/home/lk/build/output.bin"
  jq '.evaluators.session_write_exec.surface_as = "warn"' "$LANEKEEP_CONFIG_FILE" > "$LANEKEEP_CONFIG_FILE.tmp"
  mv "$LANEKEEP_CONFIG_FILE.tmp" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /home/lk/build/output.bin"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" == *"[LaneKeep] WARNING"* ]]
  [[ "$warn" == *"Write-then-execute detected (Tier 2.1)"* ]]
}

@test "t2.1: enabled=false disables detector entirely" {
  _t21_seed_write "/home/lk/build/output.bin"
  jq '.evaluators.session_write_exec.enabled = false' "$LANEKEEP_CONFIG_FILE" > "$LANEKEEP_CONFIG_FILE.tmp"
  mv "$LANEKEEP_CONFIG_FILE.tmp" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /home/lk/build/output.bin"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" != *"Write-then-execute"* ]]
}

@test "t2.1: empty exclude_extensions still detects .md (opt-out works)" {
  _t21_seed_write "/home/lk/notes.md"
  jq '.evaluators.session_write_exec.exclude_extensions = []' "$LANEKEEP_CONFIG_FILE" > "$LANEKEEP_CONFIG_FILE.tmp"
  mv "$LANEKEEP_CONFIG_FILE.tmp" "$LANEKEEP_CONFIG_FILE"
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /home/lk/notes.md"}}' | "$LANEKEEP_DIR/bin/lanekeep-handler")
  warn=$(printf '%s' "$output" | jq -r '.warn // ""')
  [[ "$warn" == *"Write-then-execute"* ]]
}
