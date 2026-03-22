#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/eval-codediff.sh"
  export LANEKEEP_CONFIG_FILE="$BATS_TEST_DIRNAME/../fixtures/lanekeep.json"
}

# AC1: Read Tool Skipped
@test "codediff_eval skips Read tool" {
  run codediff_eval "Read" '{"file_path":"x"}'
  [ "$status" -eq 0 ]
}

@test "codediff_eval Read tool reason contains 'skipped'" {
  codediff_eval "Read" '{"file_path":"x"}'
  [[ "$CODEDIFF_REASON" == *"skipped"* ]]
}

# AC2: Glob Tool Skipped
@test "codediff_eval skips Glob tool" {
  run codediff_eval "Glob" '{"pattern":"*.py"}'
  [ "$status" -eq 0 ]
}

@test "codediff_eval Glob tool reason contains 'skipped'" {
  codediff_eval "Glob" '{"pattern":"*.py"}'
  [[ "$CODEDIFF_REASON" == *"skipped"* ]]
}

# AC3: Bash Destructive Denied
@test "codediff_eval denies Bash with destructive pattern 'rm -rf'" {
  run codediff_eval "Bash" '{"command":"rm -rf /tmp"}'
  [ "$status" -eq 1 ]
}

@test "codediff_eval destructive deny reason mentions 'destructive'" {
  codediff_eval "Bash" '{"command":"rm -rf /tmp"}' || true
  [[ "$CODEDIFF_REASON" == *"[Dd]estructive"* ]] || [[ "$CODEDIFF_REASON" == *"destructive"* ]] || [[ "$CODEDIFF_REASON" == *"Destructive"* ]]
}

# AC4: Write Secret Denied
@test "codediff_eval denies Write with secret pattern 'sk-'" {
  run codediff_eval "Write" '{"content":"key=sk-1234"}'
  [ "$status" -eq 1 ]
}

@test "codediff_eval secret deny reason mentions 'secret'" {
  codediff_eval "Write" '{"content":"key=sk-1234"}' || true
  [[ "$CODEDIFF_REASON" == *"[Ss]ecret"* ]] || [[ "$CODEDIFF_REASON" == *"secret"* ]] || [[ "$CODEDIFF_REASON" == *"Secret"* ]]
}

# AC5: Edit Dangerous Git Denied
@test "codediff_eval denies Edit with dangerous git pattern 'push --force'" {
  run codediff_eval "Edit" '{"new_string":"git push --force"}'
  [ "$status" -eq 1 ]
}

@test "codediff_eval dangerous git deny reason mentions 'dangerous git'" {
  codediff_eval "Edit" '{"new_string":"git push --force"}' || true
  [[ "$CODEDIFF_REASON" == *"angerous git"* ]]
}

# AC6: Safe Bash Allowed
@test "codediff_eval allows safe Bash command 'npm test'" {
  run codediff_eval "Bash" '{"command":"npm test"}'
  [ "$status" -eq 0 ]
}

@test "codediff_eval safe Bash sets CODEDIFF_PASSED=true" {
  codediff_eval "Bash" '{"command":"npm test"}'
  [ "$CODEDIFF_PASSED" = "true" ]
}

# AC7: No Config Allows
@test "codediff_eval allows when config file does not exist" {
  LANEKEEP_CONFIG_FILE="/nonexistent/lanekeep.json"
  run codediff_eval "Write" '{"content":"sk-1234"}'
  [ "$status" -eq 0 ]
}

# AC8: Disabled Evaluator Allows
@test "codediff_eval allows when evaluator is disabled" {
  export LANEKEEP_CONFIG_FILE="$BATS_TEST_DIRNAME/../fixtures/lanekeep-codediff-disabled.json"
  run codediff_eval "Write" '{"content":"sk-1234"}'
  [ "$status" -eq 0 ]
}
