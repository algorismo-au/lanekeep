#!/usr/bin/env bats
# Tests for eval-multi-session.sh (Tier 5.6)

setup() {
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CUMULATIVE_FILE="$TEST_TMP/cumulative.json"
  export LANEKEEP_CONFIG_FILE="/nonexistent/lanekeep.json"
  unset _CFG_MULTI_DENY_RATE _CFG_MULTI_TOOL_DENY _CFG_MULTI_COST_WARN _CFG_MULTI_MIN_SESSIONS
  unset _CFG_MAX_TOTAL_COST

  source "$BATS_TEST_DIRNAME/../../lib/eval-multi-session.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# Helper: write a cumulative.json with given values
_write_cumulative() {
  local sessions="${1:-5}"
  local allow="${2:-200}"
  local deny="${3:-5}"
  local ask="${4:-0}"
  local cost="${5:-0}"
  local top_tool="${6:-}"
  local top_count="${7:-0}"

  local top_denied="{}"
  if [ -n "$top_tool" ] && [ "$top_count" -gt 0 ]; then
    top_denied=$(printf '{"Bash":%s}' "$top_count")
    if [ -n "$top_tool" ] && [ "$top_tool" != "Bash" ]; then
      top_denied=$(printf '{"%s":%s}' "$top_tool" "$top_count")
    fi
  fi

  jq -n \
    --argjson sessions "$sessions" \
    --argjson allow "$allow" \
    --argjson deny "$deny" \
    --argjson ask "$ask" \
    --argjson cost "$cost" \
    --argjson top "$top_denied" \
    '{
      total_sessions: $sessions,
      total_actions: ($allow + $deny + $ask),
      decisions: {allow: $allow, deny: $deny, ask: $ask},
      total_cost: $cost,
      top_denied_tools: $top
    }' > "$LANEKEEP_CUMULATIVE_FILE"
}

# AC1: No cumulative file — pass (skip)
@test "multi_session_eval passes when cumulative file does not exist" {
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

@test "multi_session_eval leaves MULTI_SESSION_PASSED=true when no cumfile" {
  multi_session_eval "Bash" '{}'
  [ "$MULTI_SESSION_PASSED" = "true" ]
}

# AC2: min_sessions gate — fewer than 3 sessions, skip regardless of deny rate
@test "multi_session_eval passes when session count below min_sessions (default 3)" {
  _write_cumulative 2 10 50 0   # 2 sessions, 83% deny rate — would trigger if counted
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

@test "multi_session_eval passes with exactly 2 sessions and high deny rate" {
  _write_cumulative 2 0 100 0
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC3: All-clear — 3+ sessions, low deny rate, no probing — passes
@test "multi_session_eval passes with healthy stats (low deny rate, 5 sessions)" {
  _write_cumulative 5 200 5 0   # 5 sessions, deny rate ~2.4% — below 5% default
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

@test "multi_session_eval leaves MULTI_SESSION_DECISION=ask when passing (default)" {
  _write_cumulative 5 200 5 0
  multi_session_eval "Bash" '{}'
  [ "$MULTI_SESSION_PASSED" = "true" ]
}

# AC4: Deny rate anomaly — 5%+ triggers
@test "multi_session_eval returns 1 when deny rate meets threshold (5%)" {
  # 10 deny / 200 total = 5% — meets threshold
  _write_cumulative 5 190 10 0
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "multi_session_eval sets MULTI_SESSION_PASSED=false on high deny rate" {
  _write_cumulative 5 190 10 0
  multi_session_eval "Bash" '{}' || true
  [ "$MULTI_SESSION_PASSED" = "false" ]
}

@test "multi_session_eval reason mentions deny rate" {
  _write_cumulative 5 190 10 0
  multi_session_eval "Bash" '{}' || true
  [[ "$MULTI_SESSION_REASON" == *"deny rate"* ]]
}

@test "multi_session_eval reason mentions CWE-799 on deny rate trigger" {
  _write_cumulative 5 190 10 0
  multi_session_eval "Bash" '{}' || true
  [[ "$MULTI_SESSION_REASON" == *"CWE-799"* ]]
}

# AC5: 4% deny rate — below threshold, passes
@test "multi_session_eval passes with 4% deny rate (below 5% threshold)" {
  # 8 deny / 200 total = 4%
  _write_cumulative 5 192 8 0
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC6: Tool probing — 100+ denials of one tool triggers when calling that tool
@test "multi_session_eval returns 1 on tool probing when calling the over-denied tool" {
  export _CFG_MULTI_DENY_RATE=100   # disable deny-rate check to isolate probing check
  export _CFG_MULTI_TOOL_DENY=100
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  _write_cumulative 5 900 100 0 0 "Bash" 100
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "multi_session_eval sets MULTI_SESSION_PASSED=false on tool probing" {
  export _CFG_MULTI_DENY_RATE=100
  export _CFG_MULTI_TOOL_DENY=100
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  _write_cumulative 5 900 100 0 0 "Bash" 100
  multi_session_eval "Bash" '{}' || true
  [ "$MULTI_SESSION_PASSED" = "false" ]
}

@test "multi_session_eval reason mentions tool probing" {
  export _CFG_MULTI_DENY_RATE=100
  export _CFG_MULTI_TOOL_DENY=100
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  _write_cumulative 5 900 100 0 0 "Bash" 100
  multi_session_eval "Bash" '{}' || true
  [[ "$MULTI_SESSION_REASON" == *"probing"* ]]
}

@test "multi_session_eval passes when calling a different tool than the over-denied one" {
  export _CFG_MULTI_DENY_RATE=100
  export _CFG_MULTI_TOOL_DENY=100
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  _write_cumulative 5 900 100 0 0 "Bash" 100
  run multi_session_eval "Edit" '{}'
  [ "$status" -eq 0 ]
}

# AC7: Cost escalation warning
@test "multi_session_eval returns 1 when cost exceeds warn threshold" {
  export _CFG_MULTI_DENY_RATE=100
  export _CFG_MULTI_TOOL_DENY=100000
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  export _CFG_MAX_TOTAL_COST=100
  _write_cumulative 5 200 2 0 85   # $85 of $100 = 85% — above 80% warn threshold
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 1 ]
}

@test "multi_session_eval passes when cost is below warn threshold" {
  export _CFG_MULTI_DENY_RATE=100
  export _CFG_MULTI_TOOL_DENY=100000
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  export _CFG_MAX_TOTAL_COST=100
  _write_cumulative 5 200 2 0 70   # $70 of $100 = 70% — below threshold
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

@test "multi_session_eval reason mentions cost escalation" {
  export _CFG_MULTI_DENY_RATE=100
  export _CFG_MULTI_TOOL_DENY=100000
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  export _CFG_MAX_TOTAL_COST=100
  _write_cumulative 5 200 2 0 85
  multi_session_eval "Bash" '{}' || true
  [[ "$MULTI_SESSION_REASON" == *"ost escalation"* ]]
}

@test "multi_session_eval passes when _CFG_MAX_TOTAL_COST is unset (no cost check)" {
  unset _CFG_MAX_TOTAL_COST
  export _CFG_MULTI_DENY_RATE=100
  export _CFG_MULTI_TOOL_DENY=100000
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=3
  _write_cumulative 5 200 2 0 9999  # huge cost but no budget configured
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}

# AC8: Custom min_sessions config
@test "multi_session_eval respects custom min_sessions threshold" {
  export _CFG_MULTI_DENY_RATE=5
  export _CFG_MULTI_TOOL_DENY=100
  export _CFG_MULTI_COST_WARN=80
  export _CFG_MULTI_MIN_SESSIONS=10
  _write_cumulative 5 0 100 0   # 5 sessions — below custom min of 10
  run multi_session_eval "Bash" '{}'
  [ "$status" -eq 0 ]
}
