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

@test "narration_eval Bash whitelists command when all path tokens match whitelist_paths" {
  # jq/grep/etc on a whitelisted file — the 'lanekeep' substring in the arg
  # would otherwise trip lane[- ]?keep. Whitelist should apply to Bash too.
  narration_eval "Bash" '{"command":"jq .budget lanekeep/foo.json"}' || true
  [ "$NARRATION_PASSED" = true ]
}

@test "narration_eval Bash denies when one path token escapes the whitelist" {
  # Mixed command: lanekeep/foo.json whitelisted, /etc/passwd is not.
  # ALL tokens must match — one unmatched forces fall-through to pattern scan.
  narration_eval "Bash" '{"command":"jq .x lanekeep/foo.json /etc/passwd"}' || true
  [ "$NARRATION_PASSED" = false ]
  [ "$NARRATION_DECISION" = "ask" ]
}

@test "narration_eval Bash falls through to pattern scan when no path tokens" {
  # No slash, no filename extension — no path tokens extracted.
  # Behaviour must match today: pattern scan runs, matches 'work-around'.
  narration_eval "Bash" '{"command":"echo work-around now"}' || true
  [ "$NARRATION_PASSED" = false ]
}

@test "narration_eval Bash whitelists nested .md path against **/*.md" {
  # grep for 'lane-keep' inside a whitelisted .md file — the literal in the command
  # would trip lane[- ]?keep. Whitelist skip must apply.
  narration_eval "Bash" '{"command":"grep -oiP lane-keep buildinglanekeep/specs/foo.md"}' || true
  [ "$NARRATION_PASSED" = true ]
}

@test "narration_eval Bash ignores leading-dot jq expressions during tokenization" {
  # '.budget' looks path-ish (has a dot) but is a jq program, not a path.
  # Tokenizer must skip it so the file arg alone drives the whitelist decision.
  narration_eval "Bash" '{"command":"jq .budget.max_actions lanekeep/foo.json"}' || true
  [ "$NARRATION_PASSED" = true ]
}

@test "narration_eval Bash whitelist does not affect Write path check (regression)" {
  # Write with whitelisted file_path continues to short-circuit via the file_path branch,
  # independent of the Bash tokenizer path.
  narration_eval "Write" '{"file_path":"lanekeep/README.md","content":"fragment the string to work around this"}' || true
  [ "$NARRATION_PASSED" = true ]
}
