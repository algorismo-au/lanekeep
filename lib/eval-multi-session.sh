#!/usr/bin/env bash
# shellcheck disable=SC2034  # MULTI_SESSION_* globals set here, read externally via indirection
# Tier 5.6: Cross-session governance
#
# Analyzes cumulative.json (all-time metrics across sessions) to detect
# behavioral trends that single-session evaluators can't see:
#
#   1. Deny rate anomaly: overall deny rate exceeds threshold — suggests
#      persistent policy violations or governance misconfiguration
#   2. Tool probing: single tool accounts for disproportionate denials
#      (targeted evasion across sessions)
#   3. Cost escalation: session cost approaching all-time limit faster than
#      historical average (early warning before hard budget deny)
#
# This evaluator reads cumulative.json (populated by cumulative.sh at session
# boundaries) and current session state. It does NOT write to cumulative.json.
#
# Compliance: CWE-770 (Resource Allocation), CWE-799 (Interaction Frequency)

MULTI_SESSION_PASSED=true
MULTI_SESSION_REASON="Within cross-session governance"
MULTI_SESSION_DECISION="ask"

multi_session_eval() {
  local tool_name="$1"
  local tool_input="$2"
  MULTI_SESSION_PASSED=true
  MULTI_SESSION_REASON="Within cross-session governance"
  MULTI_SESSION_DECISION="ask"

  local cumfile="${LANEKEEP_CUMULATIVE_FILE:-${PROJECT_DIR:-.}/.lanekeep/cumulative.json}"
  [ -f "$cumfile" ] || return 0

  # Resolve config thresholds
  local deny_rate_threshold="" tool_deny_threshold="" cost_warn_percent=""
  local min_sessions=""
  if [ -n "${_CFG_MULTI_DENY_RATE+x}" ]; then
    deny_rate_threshold="$_CFG_MULTI_DENY_RATE"
    tool_deny_threshold="$_CFG_MULTI_TOOL_DENY"
    cost_warn_percent="$_CFG_MULTI_COST_WARN"
    min_sessions="$_CFG_MULTI_MIN_SESSIONS"
  elif [ -f "${LANEKEEP_CONFIG_FILE:-}" ]; then
    eval "$(jq -r '
      "deny_rate_threshold=" + (.evaluators.multi_session.deny_rate_threshold // "" | tostring | @sh),
      "tool_deny_threshold=" + (.evaluators.multi_session.tool_deny_threshold // "" | tostring | @sh),
      "cost_warn_percent=" + (.evaluators.multi_session.cost_warn_percent // "" | tostring | @sh),
      "min_sessions=" + (.evaluators.multi_session.min_sessions // "" | tostring | @sh)
    ' "$LANEKEEP_CONFIG_FILE" 2>/dev/null)" || true
  fi

  # Defaults
  deny_rate_threshold="${deny_rate_threshold:-10}"   # 10% deny rate triggers
  tool_deny_threshold="${tool_deny_threshold:-30}"   # 30 denials of one tool
  cost_warn_percent="${cost_warn_percent:-80}"        # warn at 80% of total cost budget
  min_sessions="${min_sessions:-5}"                   # need 5+ sessions for meaningful data

  [[ "$deny_rate_threshold" =~ ^[0-9]+$ ]] || deny_rate_threshold=10
  [[ "$tool_deny_threshold" =~ ^[0-9]+$ ]] || tool_deny_threshold=30
  [[ "$cost_warn_percent" =~ ^[0-9]+$ ]] || cost_warn_percent=80
  [[ "$min_sessions" =~ ^[0-9]+$ ]] || min_sessions=5

  # Read cumulative stats in one jq call
  local total_sessions=0 total_actions=0
  local cum_allow=0 cum_deny=0 cum_ask=0
  local cum_cost=0 top_denied_tool="" top_denied_count=0
  eval "$(jq -r '
    "total_sessions=" + (.total_sessions // 0 | tostring | @sh),
    "total_actions=" + (.total_actions // 0 | tostring | @sh),
    "cum_allow=" + (.decisions.allow // 0 | tostring | @sh),
    "cum_deny=" + (.decisions.deny // 0 | tostring | @sh),
    "cum_ask=" + (.decisions.ask // 0 | tostring | @sh),
    "cum_cost=" + (.total_cost // 0 | tostring | @sh),
    "top_denied_tool=" + ((.top_denied_tools // {} | to_entries | sort_by(-.value) | first // {key:""}) | .key | @sh),
    "top_denied_count=" + ((.top_denied_tools // {} | to_entries | sort_by(-.value) | first // {value:0}) | .value | tostring | @sh)
  ' "$cumfile" 2>/dev/null)" || return 0

  [[ "$total_sessions" =~ ^[0-9]+$ ]] || total_sessions=0
  [[ "$total_actions" =~ ^[0-9]+$ ]] || total_actions=0
  [[ "$cum_allow" =~ ^[0-9]+$ ]] || cum_allow=0
  [[ "$cum_deny" =~ ^[0-9]+$ ]] || cum_deny=0
  [[ "$cum_ask" =~ ^[0-9]+$ ]] || cum_ask=0
  [[ "$top_denied_count" =~ ^[0-9]+$ ]] || top_denied_count=0

  # Need enough data for meaningful analysis
  if [ "$total_sessions" -lt "$min_sessions" ]; then
    return 0
  fi

  local total_decisions=$((cum_allow + cum_deny + cum_ask))
  [ "$total_decisions" -gt 0 ] || return 0

  # Check 1: Overall deny rate anomaly
  local deny_rate_pct=$(( (cum_deny * 100) / total_decisions ))
  if [ "$deny_rate_pct" -ge "$deny_rate_threshold" ]; then
    MULTI_SESSION_PASSED=false
    MULTI_SESSION_DECISION="ask"
    MULTI_SESSION_REASON="[LaneKeep] NEEDS APPROVAL — MultiSessionEvaluator (Tier 5.6)
High cross-session deny rate: ${deny_rate_pct}% (${cum_deny}/${total_decisions} decisions denied)
Threshold: ${deny_rate_threshold}% across ${total_sessions} sessions

A persistently high deny rate may indicate:
  - Governance rules too restrictive for the workflow
  - Persistent policy violations requiring team review
  - Agent configuration mismatch

Review denied patterns with: lanekeep insights --denied

Compliance: CWE-799 (Improper Control of Interaction Frequency)"
    return 1
  fi

  # Check 2: Tool probing — single tool with disproportionate denials
  if [ "$top_denied_count" -ge "$tool_deny_threshold" ] && [ "$tool_name" = "$top_denied_tool" ]; then
    MULTI_SESSION_PASSED=false
    MULTI_SESSION_DECISION="ask"
    MULTI_SESSION_REASON="[LaneKeep] NEEDS APPROVAL — MultiSessionEvaluator (Tier 5.6)
Cross-session tool probing detected: '${top_denied_tool}' denied ${top_denied_count} times
Threshold: ${tool_deny_threshold} denials for a single tool

Concentrated denials of one tool across sessions may indicate targeted
evasion attempts or a workflow that needs a rule exception.

Review with: lanekeep insights --tool ${top_denied_tool}

Compliance: CWE-799 (Improper Control of Interaction Frequency)"
    return 1
  fi

  # Check 3: Cost escalation early warning
  # Warn when cumulative cost approaches max_total_cost budget
  local max_total_cost="${_CFG_MAX_TOTAL_COST:-}"
  if [ -n "$max_total_cost" ] && [ "$max_total_cost" != "null" ]; then
    # Use jq for float comparison (cum_cost may be decimal)
    local cost_exceeded
    cost_exceeded=$(jq -rn \
      --argjson cost "$cum_cost" \
      --argjson max "$max_total_cost" \
      --argjson pct "$cost_warn_percent" \
      'if $cost > ($max * $pct / 100) then "true" else "false" end' 2>/dev/null) || cost_exceeded="false"

    if [ "$cost_exceeded" = "true" ]; then
      local display_cost display_max
      display_cost=$(jq -n --argjson v "$cum_cost" '$v * 100 | round / 100') || display_cost="$cum_cost"
      display_max="$max_total_cost"
      MULTI_SESSION_PASSED=false
      MULTI_SESSION_DECISION="ask"
      MULTI_SESSION_REASON="[LaneKeep] NEEDS APPROVAL — MultiSessionEvaluator (Tier 5.6)
Cost escalation warning: \$${display_cost} of \$${display_max} all-time budget used (${cost_warn_percent}% threshold)
Across ${total_sessions} sessions

Approaching the all-time cost limit. Budget will hard-deny at \$${display_max}.
Review spend with: lanekeep insights --cost

Compliance: CWE-770 (Allocation of Resources Without Limits)"
      return 1
    fi
  fi

  return 0
}
