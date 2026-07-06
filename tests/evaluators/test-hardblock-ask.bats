#!/usr/bin/env bats
# Control 1: escalation via hard_block_overrides "ask" — tests the new branch in eval-hardblock.sh

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/eval-hardblock.sh"
  TEST_CFG=$(mktemp --suffix=.json)
  cat > "$TEST_CFG" <<'EOF'
{
  "hard_blocks": ["mkfs", "shutdown", "reboot"],
  "hard_blocks_regex": [],
  "hard_block_overrides": {
    "mkfs": "ask",
    "shutdown": "warn"
  }
}
EOF
  export LANEKEEP_CONFIG_FILE="$TEST_CFG"
  unset _CFG_HARD_BLOCKS _CFG_HARD_BLOCKS_REGEX _CFG_HARD_BLOCK_OVERRIDES
}

teardown() {
  [ -n "${TEST_CFG:-}" ] && rm -f "$TEST_CFG"
}

@test "hardblock_check escalates mkfs to ask via override" {
  hardblock_check "Bash" '{"command":"mkfs.ext4 /dev/sda1"}' || true
  [ "$HARDBLOCK_DECISION" = "ask" ]
  [ "$HARDBLOCK_ESCALATED" = true ]
  [[ "$HARDBLOCK_REASON" == *"ESCALATED"* ]]
  [[ "$HARDBLOCK_HINT" == *"ESCALATE:"* ]]
}

@test "hardblock_check hard-denies reboot (no override)" {
  hardblock_check "Bash" '{"command":"reboot"}' || true
  [ "$HARDBLOCK_DECISION" = "deny" ]
  [ "$HARDBLOCK_ESCALATED" = false ]
  [[ "$HARDBLOCK_REASON" == *"HARD-BLOCKED"* ]]
}

@test "hardblock_check warn override preserves existing behavior (regression)" {
  hardblock_check "Bash" '{"command":"shutdown -h now"}' || true
  [ -n "$HARDBLOCK_WARNED" ]
  [[ "$HARDBLOCK_WARNED" == *"WARN"* ]]
  [ "$HARDBLOCK_ESCALATED" = false ]
}

@test "hardblock_check allows commands with no match" {
  hardblock_check "Bash" '{"command":"ls -la"}' || true
  [ -z "$HARDBLOCK_REASON" ]
  [ "$HARDBLOCK_ESCALATED" = false ]
}

@test "hardblock_check ESCALATED=false after prior ask on subsequent call (globals reset)" {
  hardblock_check "Bash" '{"command":"mkfs.ext4 /dev/sda1"}' || true
  [ "$HARDBLOCK_ESCALATED" = true ]
  hardblock_check "Bash" '{"command":"ls"}' || true
  [ "$HARDBLOCK_ESCALATED" = false ]
  [ "$HARDBLOCK_DECISION" = "deny" ]
}
