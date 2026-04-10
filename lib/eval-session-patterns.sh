#!/usr/bin/env bash
# shellcheck disable=SC2034  # SESSION_PATTERN_* globals set here, read externally via indirection
# Tier 2.6: Session anti-pattern detection
#
# Detects behavioral anti-patterns within a single session by analyzing the
# sequence of tool calls and decisions in the session event log:
#
#   1. Evasion: repeated denials of the same tool followed by variants
#      (trying different commands to achieve the same denied goal)
#   2. Rapid denial clustering: N denials within a short time window
#      (brute-force probing of governance boundaries)
#
# Event log is stored in .lanekeep/session_events.jsonl alongside state.json.
# Each line: {"tool":"...","decision":"...","epoch":...,"hash":"..."}
# The hash is a short fingerprint of the tool_input for similarity detection.
#
# Compliance: CWE-799 (Improper Control of Interaction Frequency)

SESSION_PATTERN_PASSED=true
SESSION_PATTERN_REASON="Passed"
SESSION_PATTERN_DECISION="ask"

# Record a tool call event for pattern analysis.
# Called from lanekeep-handler after each decision (allow, deny, ask).
session_pattern_record() {
  local tool_name="$1"
  local decision="$2"
  local epoch="$3"
  local tool_input="$4"

  local events_file="${LANEKEEP_STATE_FILE%.json}_events.jsonl"

  # Compute a short hash of the tool input for similarity grouping
  # Uses first 8 chars of md5 — not cryptographic, just bucketing
  local input_hash=""
  if [ -n "$tool_input" ]; then
    input_hash=$(printf '%s' "$tool_input" | md5sum 2>/dev/null | cut -c1-8) || input_hash=""
  fi

  # Append event (best-effort, non-blocking)
  printf '{"tool":"%s","decision":"%s","epoch":%s,"hash":"%s"}\n' \
    "$(_json_escape "$tool_name")" "$decision" "$epoch" "$input_hash" \
    >> "$events_file" 2>/dev/null || true
}

session_pattern_eval() {
  local tool_name="$1"
  local tool_input="$2"
  SESSION_PATTERN_PASSED=true
  SESSION_PATTERN_REASON="Passed"
  SESSION_PATTERN_DECISION="ask"

  local events_file="${LANEKEEP_STATE_FILE%.json}_events.jsonl"

  # No events yet — first call in session
  [ -f "$events_file" ] || return 0

  # Resolve config thresholds
  local evasion_threshold="" denial_cluster_threshold="" time_window=""
  if [ -n "${_CFG_SESSION_EVASION_THRESHOLD+x}" ]; then
    evasion_threshold="$_CFG_SESSION_EVASION_THRESHOLD"
    denial_cluster_threshold="$_CFG_SESSION_DENIAL_CLUSTER"
    time_window="$_CFG_SESSION_TIME_WINDOW"
  elif [ -f "${LANEKEEP_CONFIG_FILE:-}" ]; then
    eval "$(jq -r '
      "evasion_threshold=" + (.evaluators.session_patterns.evasion_threshold // "" | tostring | @sh),
      "denial_cluster_threshold=" + (.evaluators.session_patterns.denial_cluster_threshold // "" | tostring | @sh),
      "time_window=" + (.evaluators.session_patterns.time_window_seconds // "" | tostring | @sh)
    ' "$LANEKEEP_CONFIG_FILE" 2>/dev/null)" || true
  fi

  # Defaults
  evasion_threshold="${evasion_threshold:-3}"
  denial_cluster_threshold="${denial_cluster_threshold:-5}"
  time_window="${time_window:-120}"

  [[ "$evasion_threshold" =~ ^[0-9]+$ ]] || evasion_threshold=3
  [[ "$denial_cluster_threshold" =~ ^[0-9]+$ ]] || denial_cluster_threshold=5
  [[ "$time_window" =~ ^[0-9]+$ ]] || time_window=120

  # Read recent events (tail for performance — only need last N events)
  local max_scan=$(( denial_cluster_threshold * 3 ))
  [ "$max_scan" -lt 30 ] && max_scan=30
  local recent_events
  recent_events=$(tail -n "$max_scan" "$events_file" 2>/dev/null) || return 0
  [ -n "$recent_events" ] || return 0

  local now_epoch="${_NOW_EPOCH:-$(date +%s)}"
  local cutoff=$((now_epoch - time_window))

  # Check 1: Denial clustering — too many denials in the time window
  local denial_count
  denial_count=$(printf '%s' "$recent_events" | jq -r --argjson cutoff "$cutoff" '
    select(.decision == "deny" and .epoch >= $cutoff) | .tool
  ' 2>/dev/null | wc -l) || denial_count=0

  if [ "$denial_count" -ge "$denial_cluster_threshold" ]; then
    SESSION_PATTERN_PASSED=false
    SESSION_PATTERN_DECISION="ask"
    SESSION_PATTERN_REASON="[LaneKeep] NEEDS APPROVAL — SessionPatternEvaluator (Tier 2.6)
Rapid denial clustering detected: ${denial_count} denials in last ${time_window}s
Threshold: ${denial_cluster_threshold}

This pattern may indicate governance boundary probing.
Consider: /clear to reset session state if the approach has changed.

Compliance: CWE-799 (Improper Control of Interaction Frequency)"
    return 1
  fi

  # Check 2: Evasion — same tool denied N+ times (variants of the same action)
  local evasion_tool evasion_count
  evasion_tool=$(printf '%s' "$recent_events" | jq -r --argjson cutoff "$cutoff" '
    select(.decision == "deny" and .epoch >= $cutoff) | .tool
  ' 2>/dev/null | sort | uniq -c | sort -rn | head -1) || evasion_tool=""

  if [ -n "$evasion_tool" ]; then
    evasion_count=$(printf '%s' "$evasion_tool" | awk '{print $1}')
    evasion_tool=$(printf '%s' "$evasion_tool" | awk '{print $2}')
    [[ "$evasion_count" =~ ^[0-9]+$ ]] || evasion_count=0

    if [ "$evasion_count" -ge "$evasion_threshold" ] && [ "$tool_name" = "$evasion_tool" ]; then
      SESSION_PATTERN_PASSED=false
      SESSION_PATTERN_DECISION="ask"
      SESSION_PATTERN_REASON="[LaneKeep] NEEDS APPROVAL — SessionPatternEvaluator (Tier 2.6)
Possible evasion: ${evasion_count} denied '${evasion_tool}' calls in last ${time_window}s
Threshold: ${evasion_threshold} same-tool denials

Repeated denied tool calls with variations may indicate an attempt to
bypass governance rules. If the goal has changed, use /clear.

Compliance: CWE-799 (Improper Control of Interaction Frequency)"
      return 1
    fi
  fi

  return 0
}
