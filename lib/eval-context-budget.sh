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
CONTEXT_BUDGET_HINT=""
CONTEXT_BUDGET_DECISION="allow"

context_budget_eval() {
  local tool_name="$1"
  local tool_input="$2"
  CONTEXT_BUDGET_PASSED=true
  CONTEXT_BUDGET_REASON="Within context budget"
  CONTEXT_BUDGET_HINT=""
  CONTEXT_BUDGET_DECISION="allow"

  # Resolve config: pre-extracted _CFG_* > jq fallback.
  # Token-signal vars (context_window_size / soft_percent / hard_percent) and
  # action-count vars (action_warn / action_hard) are loaded independently so
  # tests / callers can seed one signal without needing to seed the other.
  local context_window_size="" soft_percent="" hard_percent="" decision=""
  local action_warn="" action_hard=""
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

  if [ -n "${_CFG_CONTEXT_ACTION_WARN+x}" ] || [ -n "${_CFG_CONTEXT_ACTION_HARD+x}" ]; then
    action_warn="${_CFG_CONTEXT_ACTION_WARN:-}"
    action_hard="${_CFG_CONTEXT_ACTION_HARD:-}"
  elif [ -f "${LANEKEEP_CONFIG_FILE:-}" ]; then
    eval "$(jq -r '
      "action_warn=" + (.budget.action_count_warn // "" | tostring | @sh),
      "action_hard=" + (.budget.action_count_hard // "" | tostring | @sh)
    ' "$LANEKEEP_CONFIG_FILE" 2>/dev/null)" || true
  fi

  # Env-var override for decision (used by both signals; tests seed this
  # without needing the whole token-signal config triad).
  if [ -n "${_CFG_CONTEXT_BUDGET_DECISION:-}" ]; then
    decision="$_CFG_CONTEXT_BUDGET_DECISION"
  fi
  # Decision default (shared between token + action-count paths)
  decision="${decision:-ask}"

  # ── Action-count signal (opt-in via .budget.action_count_warn / _hard) ──
  # Orthogonal to token utilization: catches long sessions full of cheap
  # small actions that never trip the token gate. Reads pre-increment session
  # action count exposed by eval-budget.sh as _SESSION_ACTION_COUNT.
  if [ -n "$action_hard" ] || [ -n "$action_warn" ]; then
    local session_actions="${_SESSION_ACTION_COUNT:-}"
    if [[ "$session_actions" =~ ^[0-9]+$ ]]; then
      if [[ "$action_hard" =~ ^[0-9]+$ ]] && [ "$action_hard" -gt 0 ] \
        && [ "$session_actions" -ge "$action_hard" ]; then
        CONTEXT_BUDGET_PASSED=false
        CONTEXT_BUDGET_DECISION="deny"
        CONTEXT_BUDGET_REASON="[LaneKeep] DENIED by ContextBudgetEvaluator (Tier 5.5, action-count signal, score: 1.0)
Session action count: ${session_actions}
Hard limit: ${action_hard} actions

Long sessions with many cheap actions degrade coherence even when the token gate is unmet.
Action: /clear to reset context, or /compact to free space.

Compliance: CWE-770 (Allocation of Resources Without Limits)"
        CONTEXT_BUDGET_HINT="DENIED: Session at ${session_actions} actions (hard cap ${action_hard}). Run /clear or /compact."
        return 1
      fi
      if [[ "$action_warn" =~ ^[0-9]+$ ]] && [ "$action_warn" -gt 0 ] \
        && [ "$session_actions" -ge "$action_warn" ]; then
        CONTEXT_BUDGET_PASSED=false
        CONTEXT_BUDGET_DECISION="$decision"
        CONTEXT_BUDGET_REASON="[LaneKeep] NEEDS APPROVAL — ContextBudgetEvaluator (Tier 5.5, action-count signal)
Session action count: ${session_actions}
Soft limit: ${action_warn} actions

Long sessions with many cheap actions degrade coherence even when the token gate is unmet.
Recommended: /compact or /clear before continuing.

Compliance: CWE-770 (Allocation of Resources Without Limits)"
        if [ "$decision" = "deny" ]; then
          CONTEXT_BUDGET_HINT="DENIED: Session at ${session_actions} actions (soft cap ${action_warn})."
        else
          CONTEXT_BUDGET_HINT="APPROVAL NEEDED: Session at ${session_actions} actions (soft cap ${action_warn})."
        fi
        return 1
      fi
    fi
  fi

  # ── Token utilization signal (existing) ──
  # Requires transcript data from budget evaluator (must run after Tier 5).
  # If transcript isn't available we skip token-side checks but the action-count
  # signal above may still have fired.
  if [ "$_TRANSCRIPT_AVAILABLE" != true ]; then
    return 0
  fi

  # Defaults
  context_window_size="${context_window_size:-200000}"
  soft_percent="${soft_percent:-80}"
  hard_percent="${hard_percent:-95}"

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
    CONTEXT_BUDGET_HINT="DENIED: Context window at ${utilization_pct}%. Run /clear or /compact before continuing."
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
    if [ "$decision" = "deny" ]; then
      CONTEXT_BUDGET_HINT="DENIED: Context window at ${utilization_pct}% (soft limit). Compact or clear before proceeding."
    else
      CONTEXT_BUDGET_HINT="APPROVAL NEEDED: Context window at ${utilization_pct}% (soft limit). Compact or clear before proceeding."
    fi
    return 1
  fi

  return 0
}
