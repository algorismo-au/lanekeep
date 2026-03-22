#!/usr/bin/env bats
# Tests for lanekeep rules update command (disabled — Pro feature)

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "rules update prints Pro message and exits 1" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" update
  [ "$status" -eq 1 ]
  [[ "$output" == *"not available in the open-source edition"* ]]
  [[ "$output" == *"lanekeep rules import FILE"* ]]
}

@test "rules update --check also exits 1 with Pro message" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" update --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"not available in the open-source edition"* ]]
}

@test "rules update --yes also exits 1 with Pro message" {
  run "$LANEKEEP_DIR/bin/lanekeep-rules" update --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"not available in the open-source edition"* ]]
}

@test "lanekeep rules update accessible via lanekeep CLI" {
  run "$LANEKEEP_DIR/bin/lanekeep" rules update
  [ "$status" -eq 1 ]
  [[ "$output" == *"not available in the open-source edition"* ]]
}
