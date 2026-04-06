#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/eval-hardblock.sh"
  export LANEKEEP_CONFIG_FILE="$BATS_TEST_DIRNAME/../fixtures/lanekeep.json"
}

# AC1: rm -rf Blocked
@test "hardblock_check blocks 'rm -rf' command" {
  run hardblock_check "Bash" '{"command":"rm -rf /tmp/x"}'
  [ "$status" -eq 1 ]
}

@test "hardblock_check sets HARDBLOCK_REASON containing matched pattern" {
  hardblock_check "Bash" '{"command":"rm -rf /tmp/x"}' || true
  [[ "$HARDBLOCK_REASON" == *"rm -rf"* ]]
  [[ "$HARDBLOCK_REASON" == *"HARD-BLOCKED"* ]]
}

# AC2: Safe Command Passes
@test "hardblock_check allows safe command 'npm test'" {
  run hardblock_check "Bash" '{"command":"npm test"}'
  [ "$status" -eq 0 ]
}

# AC3: Case Insensitive
@test "hardblock_check is case insensitive - 'drop table' matches 'DROP TABLE'" {
  run hardblock_check "Bash" '{"command":"drop table users"}'
  [ "$status" -eq 1 ]
}

# AC4: No False Positive
@test "hardblock_check allows 'git push origin main' (no --force)" {
  run hardblock_check "Bash" '{"command":"git push origin main"}'
  [ "$status" -eq 0 ]
}

# AC5: No Config File
@test "hardblock_check allows when config file does not exist" {
  LANEKEEP_CONFIG_FILE="/nonexistent/lanekeep.json"
  run hardblock_check "Bash" '{"command":"rm -rf /tmp/x"}'
  [ "$status" -eq 0 ]
}

# AC6: Special Characters Safe
@test "hardblock_check handles regex-special characters in input without error" {
  run hardblock_check "Bash" '{"command":"echo [test] (foo) {bar} *.txt"}'
  [ "$status" -eq 0 ]
}

# AC7: hard_block_overrides — warn
@test "hardblock_check returns 0 and warns when pattern overridden to warn" {
  export _CFG_HARD_BLOCK_OVERRIDES="rm -rf /=warn"
  run hardblock_check "Bash" '{"command":"rm -rf /tmp/x"}'
  [ "$status" -eq 0 ]
  unset _CFG_HARD_BLOCK_OVERRIDES
}

@test "hardblock_check sets HARDBLOCK_WARNED when pattern overridden to warn" {
  export _CFG_HARD_BLOCK_OVERRIDES="rm -rf /=warn"
  hardblock_check "Bash" '{"command":"rm -rf /tmp/x"}' || true
  [[ "$HARDBLOCK_WARNED" == *"WARN"* ]]
  [[ "$HARDBLOCK_WARNED" == *"overridden"* ]]
  unset _CFG_HARD_BLOCK_OVERRIDES
}

# AC8: hard_block_overrides — disable
@test "hardblock_check skips pattern entirely when overridden to disable" {
  export _CFG_HARD_BLOCK_OVERRIDES="rm -rf /=disable"
  run hardblock_check "Bash" '{"command":"rm -rf /tmp/x"}'
  [ "$status" -eq 0 ]
  unset _CFG_HARD_BLOCK_OVERRIDES
}

# AC9: non-overridden patterns still block
@test "hardblock_check still blocks patterns not in overrides" {
  export _CFG_HARD_BLOCK_OVERRIDES="| sh=warn"
  run hardblock_check "Bash" '{"command":"rm -rf /tmp/x"}'
  [ "$status" -eq 1 ]
  unset _CFG_HARD_BLOCK_OVERRIDES
}
