#!/usr/bin/env bats
# Tests for eval-context-budget.sh (Tier 5.5)

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/eval-context-budget.sh"
  export LANEKEEP_CONFIG_FILE="/nonexistent/lanekeep.json"
  export _TRANSCRIPT_AVAILABLE=true
  export _TRANSCRIPT_INPUT_TOKENS=0
  unset _CFG_CONTEXT_WINDOW_SIZE _CFG_CONTEXT_SOFT_PERCENT _CFG_CONTEXT_HARD_PERCENT _CFG_CONTEXT_BUDGET_DECISION
}

# AC1: Below soft threshold — passes
@test "context_budget_eval allows when tokens well below soft threshold" {
  _TRANSCRIPT_INPUT_TOKENS=50000   # 25% of 200k default
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

@test "context_budget_eval leaves CONTEXT_BUDGET_DECISION=allow when below threshold" {
  _TRANSCRIPT_INPUT_TOKENS=50000
  context_budget_eval "Bash" '{}'
  [ "$CONTEXT_BUDGET_DECISION" = "allow" ]
}

# AC2: Soft threshold hit (>= 80%)
@test "context_budget_eval returns 1 at soft threshold (80%)" {
  _TRANSCRIPT_INPUT_TOKENS=160000  # exactly 80% of 200k
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "context_budget_eval sets CONTEXT_BUDGET_DECISION=ask at soft threshold" {
  _TRANSCRIPT_INPUT_TOKENS=160000
  context_budget_eval "Bash" '{}' || true
  [ "$CONTEXT_BUDGET_DECISION" = "ask" ]
}

@test "context_budget_eval includes utilization pct in reason at soft threshold" {
  _TRANSCRIPT_INPUT_TOKENS=160000
  context_budget_eval "Bash" '{}' || true
  [[ "$CONTEXT_BUDGET_REASON" == *"80%"* ]]
}

@test "context_budget_eval sets CONTEXT_BUDGET_PASSED=false at soft threshold" {
  _TRANSCRIPT_INPUT_TOKENS=160000
  context_budget_eval "Bash" '{}' || true
  [ "$CONTEXT_BUDGET_PASSED" = "false" ]
}

# AC3: Hard threshold hit (>= 95%) — deny
@test "context_budget_eval returns 1 at hard threshold (95%)" {
  _TRANSCRIPT_INPUT_TOKENS=190000  # 95% of 200k
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "context_budget_eval sets CONTEXT_BUDGET_DECISION=deny at hard threshold" {
  _TRANSCRIPT_INPUT_TOKENS=190000
  context_budget_eval "Bash" '{}' || true
  [ "$CONTEXT_BUDGET_DECISION" = "deny" ]
}

@test "context_budget_eval reason mentions DENIED at hard threshold" {
  _TRANSCRIPT_INPUT_TOKENS=190000
  context_budget_eval "Bash" '{}' || true
  [[ "$CONTEXT_BUDGET_REASON" == *"DENIED"* ]]
}

@test "context_budget_eval reason mentions CWE-770 at hard threshold" {
  _TRANSCRIPT_INPUT_TOKENS=190000
  context_budget_eval "Bash" '{}' || true
  [[ "$CONTEXT_BUDGET_REASON" == *"CWE-770"* ]]
}

# AC4: No transcript data — skip (pass)
@test "context_budget_eval skips when _TRANSCRIPT_AVAILABLE is not true" {
  _TRANSCRIPT_AVAILABLE=false
  _TRANSCRIPT_INPUT_TOKENS=199000
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

@test "context_budget_eval skips when _TRANSCRIPT_AVAILABLE is unset" {
  unset _TRANSCRIPT_AVAILABLE
  _TRANSCRIPT_INPUT_TOKENS=199000
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC5: Config overrides via _CFG_* env vars
@test "context_budget_eval respects custom window size via _CFG_CONTEXT_WINDOW_SIZE" {
  export _CFG_CONTEXT_WINDOW_SIZE=100000
  export _CFG_CONTEXT_SOFT_PERCENT=80
  export _CFG_CONTEXT_HARD_PERCENT=95
  _TRANSCRIPT_INPUT_TOKENS=80000   # 80% of 100k — hits soft
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "context_budget_eval respects custom soft percent via _CFG_CONTEXT_SOFT_PERCENT" {
  export _CFG_CONTEXT_WINDOW_SIZE=200000
  export _CFG_CONTEXT_SOFT_PERCENT=50
  export _CFG_CONTEXT_HARD_PERCENT=95
  _TRANSCRIPT_INPUT_TOKENS=100000  # 50% — hits the lowered soft threshold
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "context_budget_eval respects custom hard percent via _CFG_CONTEXT_HARD_PERCENT" {
  export _CFG_CONTEXT_WINDOW_SIZE=200000
  export _CFG_CONTEXT_SOFT_PERCENT=80
  export _CFG_CONTEXT_HARD_PERCENT=85
  _TRANSCRIPT_INPUT_TOKENS=170000  # 85% — hits the lowered hard threshold
  context_budget_eval "Bash" '{}' || true
  [ "$CONTEXT_BUDGET_DECISION" = "deny" ]
}

# AC6: Exact boundary — 79% is below soft (passes)
@test "context_budget_eval allows at 79% utilization (just below soft threshold)" {
  _TRANSCRIPT_INPUT_TOKENS=158000  # 79% of 200k
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC7: Invalid config values are handled gracefully
@test "context_budget_eval passes when context_window_size is zero (safety guard)" {
  export _CFG_CONTEXT_WINDOW_SIZE=0
  export _CFG_CONTEXT_SOFT_PERCENT=80
  export _CFG_CONTEXT_HARD_PERCENT=95
  _TRANSCRIPT_INPUT_TOKENS=199000
  run context_budget_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}
