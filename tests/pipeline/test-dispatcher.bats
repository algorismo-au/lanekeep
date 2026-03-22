#!/usr/bin/env bats
# Tests for lib/dispatcher.sh — format_denial function

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$LANEKEEP_DIR/lib/dispatcher.sh"
}

@test "format_denial includes primary reason" {
  local result1='{"name":"HardBlock","tier":0,"score":1.0,"passed":false,"detail":"HARD-BLOCKED"}'
  output=$(format_denial "Primary deny reason" "$result1")
  [[ "$output" == *"Primary deny reason"* ]]
}

@test "format_denial includes Evaluation Summary header" {
  local result1='{"name":"HardBlock","tier":0,"score":1.0,"passed":false,"detail":"HARD-BLOCKED"}'
  output=$(format_denial "Primary deny reason" "$result1")
  [[ "$output" == *"Evaluation Summary"* ]]
}

@test "format_denial shows [FAIL] for failed evaluator" {
  local result1='{"name":"SchemaEvaluator","tier":1,"score":1.0,"passed":false,"detail":"Tool not allowed"}'
  output=$(format_denial "Schema deny" "$result1")
  [[ "$output" == *"[FAIL] SchemaEvaluator (Tier 1)"* ]]
}

@test "format_denial shows [PASS] for passed evaluator" {
  local result_pass='{"name":"SchemaEvaluator","tier":1,"score":0,"passed":true,"detail":"Tool allowed"}'
  local result_fail='{"name":"CodeDiffEvaluator","tier":2,"score":0.9,"passed":false,"detail":"Secret detected"}'
  output=$(format_denial "CodeDiff deny" "$result_pass" "$result_fail")
  [[ "$output" == *"[PASS] SchemaEvaluator (Tier 1)"* ]]
  [[ "$output" == *"[FAIL] CodeDiffEvaluator (Tier 2)"* ]]
}

@test "format_denial with multiple results shows all" {
  local r1='{"name":"HardBlock","tier":0,"score":0,"passed":true,"detail":"OK"}'
  local r2='{"name":"SchemaEvaluator","tier":1,"score":0,"passed":true,"detail":"OK"}'
  local r3='{"name":"CodeDiffEvaluator","tier":2,"score":0.9,"passed":false,"detail":"Secret found"}'
  output=$(format_denial "Denied" "$r1" "$r2" "$r3")
  [[ "$output" == *"[PASS] HardBlock"* ]]
  [[ "$output" == *"[PASS] SchemaEvaluator"* ]]
  [[ "$output" == *"[FAIL] CodeDiffEvaluator"* ]]
}
