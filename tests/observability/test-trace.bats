#!/usr/bin/env bats
# Tests for lib/trace.sh (write_trace) and bin/lanekeep-trace (CLI viewer)

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_SESSION_ID="test-session-001"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test-session-001.jsonl"
  mkdir -p "$TEST_TMP/.lanekeep/traces"

  source "$LANEKEEP_DIR/lib/trace.sh"
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

# --- AC 1: write_trace Creates Valid JSONL ---
@test "write_trace creates valid JSONL line" {
  local result='{"name":"SchemaEvaluator","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Read" '{"file_path":"x.txt"}' "allow" "" "3" "$result"
  [ -f "$LANEKEEP_TRACE_FILE" ]
  # Must be valid JSON
  jq '.' "$LANEKEEP_TRACE_FILE" >/dev/null
}

# --- AC 2: Trace Has Required Fields ---
@test "trace entry contains required fields" {
  local result='{"name":"SchemaEvaluator","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Bash" '{"command":"ls"}' "allow" "" "5" "$result"
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  # Check all required fields exist
  [ "$(printf '%s' "$line" | jq -r '.timestamp')" != "null" ]
  [ "$(printf '%s' "$line" | jq -r '.session_id')" = "test-session-001" ]
  [ "$(printf '%s' "$line" | jq -r '.tool_name')" = "Bash" ]
  [ "$(printf '%s' "$line" | jq -r '.decision')" = "allow" ]
  [ "$(printf '%s' "$line" | jq '.evaluators | length')" -ge 1 ]
  [ "$(printf '%s' "$line" | jq '.ralph')" != "null" ]
}

# --- AC 3: Multiple Writes Append ---
@test "three write_trace calls produce 3 lines" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Read" '{}' "allow" "" "1" "$result"
  write_trace "Bash" '{}' "deny" "blocked" "2" "$result"
  write_trace "Write" '{}' "allow" "" "3" "$result"
  line_count=$(wc -l < "$LANEKEEP_TRACE_FILE")
  [ "$line_count" -eq 3 ]
}

# --- AC 4: lanekeep trace Displays Pretty-Printed JSON ---
@test "lanekeep trace pretty-prints trace file" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Read" '{"file_path":"a.txt"}' "allow" "" "1" "$result"

  # lanekeep-trace needs to find traces in .lanekeep/traces/ under PROJECT_DIR
  export PROJECT_DIR="$TEST_TMP"

  output=$("$LANEKEEP_DIR/bin/lanekeep-trace")
  # Pretty-printed JSON has indentation (2+ spaces)
  [[ "$output" == *"  "* ]]
  # Contains tool_name
  [[ "$output" == *"Read"* ]]
}

# --- AC 5: lanekeep trace --follow Tails ---
@test "lanekeep trace --follow shows new entries" {
  export PROJECT_DIR="$TEST_TMP"
  local trace_file="$LANEKEEP_TRACE_FILE"

  # Write initial entry
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Read" '{}' "allow" "" "1" "$result"

  # Start follow in background, capture output
  "$LANEKEEP_DIR/bin/lanekeep-trace" --follow > "$TEST_TMP/follow-output" 2>/dev/null 3>&- &
  FOLLOW_PID=$!

  # Give tail -f time to start
  sleep 0.3

  # Append a new entry
  jq -n -c '{tool_name:"NewEntry",decision:"deny"}' >> "$trace_file"

  # Give time for output
  sleep 0.3
  pkill -P "$FOLLOW_PID" 2>/dev/null || true
  kill "$FOLLOW_PID" 2>/dev/null || true
  wait "$FOLLOW_PID" 2>/dev/null || true

  output=$(cat "$TEST_TMP/follow-output")
  [[ "$output" == *"NewEntry"* ]]
}

# --- No trace files found ---
@test "lanekeep trace with no trace files shows message" {
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  # No .jsonl files in traces dir
  run "$LANEKEEP_DIR/bin/lanekeep-trace"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No trace files"* ]]
}

# --- Ralph defaults when ralph-context.sh unavailable ---
@test "write_trace uses ralph defaults when ralph-context.sh missing" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Read" '{}' "allow" "" "1" "$result"
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  ralph=$(printf '%s' "$line" | jq -c '.ralph')
  # Should have default ralph context (not null)
  [ "$ralph" != "null" ]
  [ "$(printf '%s' "$ralph" | jq -r '.iteration')" = "0" ]
}

# --- File path extraction for Write/Edit/Read ---
@test "write_trace promotes file_path from tool_input for Write/Edit/Read" {
  local result='{"name":"SchemaEvaluator","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Write" '{"file_path":"/tmp/foo.txt","content":"hello"}' "allow" "" "2" "$result"
  write_trace "Edit" '{"file_path":"/tmp/bar.sh","old_string":"x","new_string":"y"}' "allow" "" "3" "$result"
  write_trace "Read" '{"file_path":"/tmp/baz.md"}' "allow" "" "1" "$result"

  # All three entries should have top-level file_path
  local line1 line2 line3
  line1=$(sed -n '1p' "$LANEKEEP_TRACE_FILE")
  line2=$(sed -n '2p' "$LANEKEEP_TRACE_FILE")
  line3=$(sed -n '3p' "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line1" | jq -r '.file_path')" = "/tmp/foo.txt" ]
  [ "$(printf '%s' "$line2" | jq -r '.file_path')" = "/tmp/bar.sh" ]
  [ "$(printf '%s' "$line3" | jq -r '.file_path')" = "/tmp/baz.md" ]
}

# --- Bash tool should NOT have file_path ---
@test "write_trace omits file_path for Bash tool" {
  local result='{"name":"SchemaEvaluator","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Bash" '{"command":"ls -la"}' "allow" "" "2" "$result"

  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.file_path // "absent"')" = "absent" ]
}

# --- Privacy: <private> tag stripping ---
@test "write_trace strips <private> tag bodies from tool_input" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Bash" '{"command":"echo <private>my-token-abc</private> done"}' "allow" "" "1" "$result"
  local line cmd
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  cmd=$(printf '%s' "$line" | jq -r '.tool_input.command')
  [[ "$cmd" == *"[REDACTED:private]"* ]]
  [[ "$cmd" != *"my-token-abc"* ]]
}

# --- Privacy: *_KEY/*_TOKEN/*_SECRET/*_PASSWORD key-name redaction ---
@test "write_trace redacts values keyed by *_KEY suffix (case-insensitive)" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Bash" '{"API_KEY":"sk-abc-123","my_key":"plaintext"}' "allow" "" "1" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.tool_input.API_KEY')" = "[REDACTED:keyname]" ]
  [ "$(printf '%s' "$line" | jq -r '.tool_input.my_key')" = "[REDACTED:keyname]" ]
}

@test "write_trace redacts values keyed by *_TOKEN, *_SECRET, *_PASSWORD" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Bash" '{"GH_TOKEN":"ghp_xyz","FOO_SECRET":"abc","DB_PASSWORD":"hunter2"}' "allow" "" "1" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.tool_input.GH_TOKEN')" = "[REDACTED:keyname]" ]
  [ "$(printf '%s' "$line" | jq -r '.tool_input.FOO_SECRET')" = "[REDACTED:keyname]" ]
  [ "$(printf '%s' "$line" | jq -r '.tool_input.DB_PASSWORD')" = "[REDACTED:keyname]" ]
}

@test "write_trace preserves prose containing the word 'token'" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Bash" '{"command":"grep -r token /var/log"}' "allow" "" "1" "$result"
  local line cmd
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  cmd=$(printf '%s' "$line" | jq -r '.tool_input.command')
  [ "$cmd" = "grep -r token /var/log" ]
}

@test "write_trace leaves decision/reason intact when redacting tool_input" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Bash" '{"API_KEY":"sk-abc","cmd":"x"}' "deny" "blocked because of token policy" "2" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.decision')" = "deny" ]
  [ "$(printf '%s' "$line" | jq -r '.reason')" = "blocked because of token policy" ]
}

@test "write_trace fast-path leaves Read input untouched (no secrets)" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  write_trace "Read" '{"file_path":"/etc/hosts"}' "allow" "" "1" "$result"
  local line fp
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  fp=$(printf '%s' "$line" | jq -r '.tool_input.file_path')
  [ "$fp" = "/etc/hosts" ]
}

# --- AG-007: agent_team_id / story_id / epic_id correlation fields ---

@test "AG-007: agent_team_id appears when LANEKEEP_AGENT_TEAM_ID is set" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  LANEKEEP_AGENT_TEAM_ID="team-alpha-001" write_trace "Read" '{}' "allow" "" "1" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.agent_team_id')" = "team-alpha-001" ]
}

@test "AG-007: story_id appears when LANEKEEP_STORY_ID is set" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  LANEKEEP_STORY_ID="STORY-42" write_trace "Bash" '{"command":"ls"}' "allow" "" "2" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.story_id')" = "STORY-42" ]
}

@test "AG-007: epic_id appears when LANEKEEP_EPIC_ID is set" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  LANEKEEP_EPIC_ID="EPIC-7" write_trace "Write" '{"file_path":"x.sh"}' "allow" "" "3" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.epic_id')" = "EPIC-7" ]
}

@test "AG-007: all three correlation fields appear together when all env vars set" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  LANEKEEP_AGENT_TEAM_ID="team-beta" LANEKEEP_STORY_ID="STORY-99" LANEKEEP_EPIC_ID="EPIC-3" \
    write_trace "Read" '{}' "allow" "" "1" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.agent_team_id')" = "team-beta" ]
  [ "$(printf '%s' "$line" | jq -r '.story_id')" = "STORY-99" ]
  [ "$(printf '%s' "$line" | jq -r '.epic_id')" = "EPIC-3" ]
}

@test "AG-007: agent_team_id absent from trace when LANEKEEP_AGENT_TEAM_ID unset" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  unset LANEKEEP_AGENT_TEAM_ID
  write_trace "Read" '{}' "allow" "" "1" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.agent_team_id // "absent"')" = "absent" ]
}

@test "AG-007: story_id absent from trace when LANEKEEP_STORY_ID unset" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  unset LANEKEEP_STORY_ID
  write_trace "Read" '{}' "allow" "" "1" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.story_id // "absent"')" = "absent" ]
}

@test "AG-007: epic_id absent from trace when LANEKEEP_EPIC_ID unset" {
  local result='{"name":"Test","tier":1,"score":0,"passed":true,"detail":"ok"}'
  unset LANEKEEP_EPIC_ID
  write_trace "Read" '{}' "allow" "" "1" "$result"
  local line
  line=$(head -1 "$LANEKEEP_TRACE_FILE")
  [ "$(printf '%s' "$line" | jq -r '.epic_id // "absent"')" = "absent" ]
}
