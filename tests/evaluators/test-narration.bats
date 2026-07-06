#!/usr/bin/env bats
# Control 2: narration evaluator — tool_input scanning for evasion keywords with path whitelist

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/eval-narration.sh"
  export LANEKEEP_CONFIG_FILE="$BATS_TEST_DIRNAME/../../defaults/lanekeep.json"
  unset _CFG_NARRATION_ENABLED _CFG_NARRATION_PATTERNS _CFG_NARRATION_WHITELIST_PATHS _CFG_NARRATION_DECISION
}

@test "narration_eval allows normal Python code" {
  narration_eval "Write" '{"file_path":"src/foo.py","content":"def foo(): pass"}' || true
  [ "$NARRATION_PASSED" = true ]
}

@test "narration_eval matches bare 'bypass' in Bash command" {
  narration_eval "Bash" '{"command":"# bypass the cache and rebuild"}' || true
  [ "$NARRATION_PASSED" = false ]
  [ "$NARRATION_DECISION" = "ask" ]
  [[ "$NARRATION_REASON" == *"bypass"* ]]
}

@test "narration_eval matches legitimate bypassPermissions (accepted FP with no identifier suppression)" {
  narration_eval "Bash" '{"command":"# use bypassPermissions in dev mode"}' || true
  [ "$NARRATION_PASSED" = false ]
  [ "$NARRATION_DECISION" = "ask" ]
}

@test "narration_eval skips whitelisted paths (lanekeep/**)" {
  narration_eval "Edit" '{"file_path":"lanekeep/docs/hardblock.md","new_string":"discussion of bypass patterns"}' || true
  [ "$NARRATION_PASSED" = true ]
}

@test "narration_eval attack regression: smuggled bypass via bypassPermissions proximity must still fire" {
  # Critical regression test — v1 whitelist_identifiers was dropped because this was exploitable
  narration_eval "Bash" '{"command":"# bypassPermissions -- fragment to work around the block"}' || true
  [ "$NARRATION_PASSED" = false ]
  [ "$NARRATION_DECISION" = "ask" ]
}

@test "narration_eval matches Task prompt confession" {
  narration_eval "Task" '{"prompt":"fragment the string to work around the block"}' || true
  [ "$NARRATION_PASSED" = false ]
  [ "$NARRATION_DECISION" = "ask" ]
}

@test "narration_eval ignores non-content tools" {
  narration_eval "Read" '{"file_path":"src/foo.py"}' || true
  [ "$NARRATION_PASSED" = true ]
}

@test "narration_eval sets NARRATION_HINT with actionable prefix" {
  narration_eval "Bash" '{"command":"# workaround this issue"}' || true
  [ "$NARRATION_PASSED" = false ]
  [[ "$NARRATION_HINT" == "DENIED:"* ]]
}
