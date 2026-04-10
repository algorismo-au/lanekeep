#!/usr/bin/env bash
# shellcheck disable=SC2034  # CONTEXT_BUDGET_* globals set here, read externally via indirection
# Tier 5.5: Context window saturation governance
#
# Monitors context window utilization via transcript token counts (already
# extracted by eval-budget.sh's read_transcript_tokens()) and enforces soft
# ("ask") and hard ("deny") thresholds.
#
# Rationale: context window management is the #1 performance lever for AI
# coding agents. Sessions that exceed ~80% context utilization show degraded
# output quality. At 95%+ the agent compacts or fails mid-task.
#
# This evaluator gives teams a governance knob to prevent silent degradation.
#
# Compliance: CWE-770 (Allocation of Resources Without Limits)

CONTEXT_BUDGET_PASSED=true
CONTEXT_BUDGET_REASON="Within context budget"
CONTEXT_BUDGET_DECISION="allow"

context_budget_eval() {
  local tool_name="$1"
  local tool_input="$2"
  CONTEXT_BUDGET_PASSED=true
  CONTEXT_BUDGET_REASON="Within context budget"
  CONTEXT_BUDGET_DECISION="allow"

  # Requires transcript data from budget evaluator (must run after Tier 5)
  if [ "$_TRANSCRIPT_AVAILABLE" != true ]; then
    return 0
  fi

  # Resolve config: pre-extracted _CFG_* > jq fallback
  local context_window_size="" soft_percent="" hard_percent="" decision=""
  if [ -n "${_CFG_CONTEXT_WINDOW_SIZE+x}" ]; then
    context_window_size="$_CFG_CONTEXT_WINDOW_SIZE"
    soft_percent="$_CFG_CONTEXT_SOFT_PERCENT"
    hard_percent="$_CFG_CONTEXT_HARD_PERCENT"
    decision="${_CFG_CONTEXT_BUDGET_DECISION:-ask}"
  elif [ -f "${LANEKEEP_CONFIG_FILE:-}" ]; then
    eval "$(jq -r '
      "context_window_size=" + (.budget.context_window_size // "" | tostring | @sh),
      "soft_percent=" + (.budget.context_soft_percent // "" | tostring | @sh),
      "hard_percent=" + (.budget.context_hard_percent // "" | tostring | @sh),
      "decision=" + (.evaluators.context_budget.decision // "ask" | @sh)
    ' "$LANEKEEP_CONFIG_FILE" 2>/dev/null)" || true
  fi

  # Defaults
  context_window_size="${context_window_size:-200000}"
  soft_percent="${soft_percent:-80}"
  hard_percent="${hard_percent:-95}"
  decision="${decision:-ask}"

  # Validate: must be integers
  [[ "$context_window_size" =~ ^[0-9]+$ ]] || return 0
  [[ "$soft_percent" =~ ^[0-9]+$ ]] || soft_percent=80
  [[ "$hard_percent" =~ ^[0-9]+$ ]] || hard_percent=95
  [ "$context_window_size" -gt 0 ] || return 0

  # Compute utilization percentage (integer math, multiply first to avoid truncation)
  local utilization_pct=$(( (_TRANSCRIPT_INPUT_TOKENS * 100) / context_window_size ))

  # Hard limit: deny
  if [ "$utilization_pct" -ge "$hard_percent" ]; then
    CONTEXT_BUDGET_PASSED=false
    CONTEXT_BUDGET_DECISION="deny"
    CONTEXT_BUDGET_REASON="[LaneKeep] DENIED by ContextBudgetEvaluator (Tier 5.5, score: 1.0)
Context window critically full: ${utilization_pct}% (${_TRANSCRIPT_INPUT_TOKENS}/${context_window_size} tokens)
Hard limit: ${hard_percent}%

Action: /clear to reset context, or /compact to free space.
Quality degrades severely at this utilization level.

Compliance: CWE-770 (Allocation of Resources Without Limits)"
    return 1
  fi

  # Soft limit: ask (or configured decision)
  if [ "$utilization_pct" -ge "$soft_percent" ]; then
    CONTEXT_BUDGET_PASSED=false
    CONTEXT_BUDGET_DECISION="$decision"
    CONTEXT_BUDGET_REASON="[LaneKeep] NEEDS APPROVAL — ContextBudgetEvaluator (Tier 5.5)
Context window filling up: ${utilization_pct}% (${_TRANSCRIPT_INPUT_TOKENS}/${context_window_size} tokens)
Soft limit: ${soft_percent}%

Recommended: /compact or /clear before continuing.
Output quality degrades as context fills.

Compliance: CWE-770 (Allocation of Resources Without Limits)"
    return 1
  fi

  return 0
}
