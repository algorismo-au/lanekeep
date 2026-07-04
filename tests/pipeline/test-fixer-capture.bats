#!/usr/bin/env bats
# Tests for Phase 1 #5: Tier-9 advisory verdicts fire a `fixer add` capture.
#
# Contract:
# - `warn` action  (advisory)          → fixer add fired with correct flags
# - `block` action (deny)              → no fixer add
# - `allow` action (clean)             → no fixer add
# - missing fixer binary               → tool response still OK (fail-open)

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TASKSPEC_FILE="$TEST_TMP/taskspec.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test.jsonl"
  export LANEKEEP_SESSION_ID="test-fixer-capture"
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"

  # Fixer stub: log every invocation to a file so tests can inspect flags.
  FIXER_LOG="$TEST_TMP/fixer.log"
  export FIXER_LOG
  cat > "$TEST_TMP/fixer" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXER_LOG"
STUB
  chmod +x "$TEST_TMP/fixer"
  # Keep sh + coreutils on PATH — prepend TEST_TMP so our stub wins for `fixer`.
  export PATH="$TEST_TMP:$PATH"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

_set_rt_action() {
  jq --arg a "$1" '.evaluators.result_transform.on_detect = $a' \
     "$LANEKEEP_CONFIG_FILE" > "$TEST_TMP/tmp.json" \
    && mv "$TEST_TMP/tmp.json" "$LANEKEEP_CONFIG_FILE"
}

_post_tooluse() {
  local response="$1" file_path="${2:-/tmp/target.txt}" session="${3:-sess-abc}"
  # AKIA[16 A-Z0-9] pattern is what ResultTransform's default AWS-key detector
  # matches; using it here lets us drive the warn / block paths without a
  # bespoke config change.
  jq -nc \
    --arg r "$response" \
    --arg fp "$file_path" \
    --arg sess "$session" \
    '{tool_name:"Bash",
      tool_input:{command:"echo hi",file_path:$fp},
      tool_response:$r,
      hook_event_name:"PostToolUse",
      session_id:$sess}'
}

@test "PostToolUse warn (advisory) fires fixer add with correct flags" {
  _set_rt_action warn
  output=$(_post_tooluse "AKIAIOSFODNN7EXAMPLE" "/x/y.txt" "sess-42" \
             | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
  [ -n "$(printf '%s' "$output" | jq -r '.warn // empty')" ]

  # Wait for backgrounded fixer capture (handler caps it at 200ms).
  sleep 0.5
  [ -s "$FIXER_LOG" ]
  grep -q 'add' "$FIXER_LOG"
  grep -q 'noticed-during' "$FIXER_LOG"
  grep -q 'needs-decision' "$FIXER_LOG"
  grep -q 'lanekeep@sess-42' "$FIXER_LOG"
  grep -q '/x/y.txt' "$FIXER_LOG"
}

@test "PostToolUse block (deny) does NOT fire fixer add" {
  _set_rt_action block
  _post_tooluse "AKIAIOSFODNN7EXAMPLE" "/x/y.txt" "sess-deny" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" >/dev/null
  sleep 0.5
  [ ! -s "$FIXER_LOG" ]
}

@test "PostToolUse clean allow does NOT fire fixer add" {
  _set_rt_action warn
  _post_tooluse "totally clean output" "/x/y.txt" "sess-clean" \
    | "$LANEKEEP_DIR/bin/lanekeep-handler" >/dev/null
  sleep 0.5
  [ ! -s "$FIXER_LOG" ]
}

@test "PostToolUse warn survives missing fixer binary (fail-open)" {
  _set_rt_action warn
  # Remove our stub and drop it from PATH so `command -v fixer` fails.
  rm -f "$TEST_TMP/fixer"
  export PATH="${PATH#"$TEST_TMP":}"
  # Guard: make sure fixer really isn't found in this test's PATH.
  run command -v fixer
  [ "$status" -ne 0 ]

  output=$(_post_tooluse "AKIAIOSFODNN7EXAMPLE" "/x/y.txt" "sess-nofixer" \
             | "$LANEKEEP_DIR/bin/lanekeep-handler")
  decision=$(printf '%s' "$output" | jq -r '.decision')
  [ "$decision" = "allow" ]
  [ -n "$(printf '%s' "$output" | jq -r '.warn // empty')" ]
}
