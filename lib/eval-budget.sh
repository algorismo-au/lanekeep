#!/usr/bin/env bash
# shellcheck disable=SC2034  # BUDGET_PASSED, BUDGET_REASON set here, read externally via indirection
# Tier 5: Budget tracking (action count, wall-clock time, token tracking)

BUDGET_PASSED=true
BUDGET_REASON=""

# Estimate token count from a string (~4 chars per token)
estimate_tokens() {
  local text="$1"
  local char_count=${#text}
  echo $(( (char_count + 3) / 4 ))
}

# Read real input token count from Claude Code transcript JSONL.
# The last assistant entry's usage contains the current context window size.
# Sets: _TRANSCRIPT_INPUT_TOKENS, _TRANSCRIPT_AVAILABLE, _TRANSCRIPT_MODEL,
#       _TRANSCRIPT_CACHE_CREATION_TOKENS, _TRANSCRIPT_CACHE_READ_TOKENS
_TRANSCRIPT_INPUT_TOKENS=0
_TRANSCRIPT_AVAILABLE=false
_TRANSCRIPT_MODEL=""
_TRANSCRIPT_CACHE_CREATION_TOKENS=0
_TRANSCRIPT_CACHE_READ_TOKENS=0
read_transcript_tokens() {
  _TRANSCRIPT_INPUT_TOKENS=0
  _TRANSCRIPT_AVAILABLE=false
  _TRANSCRIPT_MODEL=""
  _TRANSCRIPT_CACHE_CREATION_TOKENS=0
  _TRANSCRIPT_CACHE_READ_TOKENS=0

  local path="${TRANSCRIPT_PATH:-}"
  [ -n "$path" ] && [ -f "$path" ] && [ -r "$path" ] || return 0

  # Read last assistant entry from end of file (O(1) seek)
  local last_assistant
  last_assistant=$(tail -c 65536 "$path" 2>/dev/null | tac 2>/dev/null | grep -m1 '"type":"assistant"' 2>/dev/null) || return 0
  [ -n "$last_assistant" ] || return 0

  # Extract input tokens (total + cache breakdown) and model name in one jq call
  local _jq_out
  _jq_out=$(printf '%s' "$last_assistant" | jq -r '
    [(.message.usage // {} |
      ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))),
     (.message.usage // {} | .cache_creation_input_tokens // 0),
     (.message.usage // {} | .cache_read_input_tokens // 0),
     (.message.model // "")]
    | @tsv
  ' 2>/dev/null) || return 0

  # Parse 4 tab-separated fields: total_input, cache_creation, cache_read, model
  local _f1 _f2 _f3 _f4
  IFS=$'\t' read -r _f1 _f2 _f3 _f4 <<< "$_jq_out"
  _TRANSCRIPT_INPUT_TOKENS="${_f1:-0}"
  _TRANSCRIPT_CACHE_CREATION_TOKENS="${_f2:-0}"
  _TRANSCRIPT_CACHE_READ_TOKENS="${_f3:-0}"
  _TRANSCRIPT_MODEL="${_f4:-}"

  [[ "$_TRANSCRIPT_INPUT_TOKENS" =~ ^[0-9]+$ ]] || _TRANSCRIPT_INPUT_TOKENS=0
  [[ "$_TRANSCRIPT_CACHE_CREATION_TOKENS" =~ ^[0-9]+$ ]] || _TRANSCRIPT_CACHE_CREATION_TOKENS=0
  [[ "$_TRANSCRIPT_CACHE_READ_TOKENS" =~ ^[0-9]+$ ]] || _TRANSCRIPT_CACHE_READ_TOKENS=0
  [ "$_TRANSCRIPT_INPUT_TOKENS" -gt 0 ] && _TRANSCRIPT_AVAILABLE=true
}

budget_eval() {
  BUDGET_PASSED=true
  BUDGET_REASON="Within budget"

  local state="$LANEKEEP_STATE_FILE"
  local tool_input="${1:-}"
  local now_epoch="${2:-$(date +%s)}"
  local already_blocked="${3:-}"
  local token_mode="${4:-input}"
  local cc_session_id="${5:-}"
  local skip_increment="${6:-false}"  # skip counter increment (for "ask" decisions)

  # Initialize state file if missing
  if [ ! -f "$state" ]; then
    printf '{"action_count":0,"token_count":0,"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"total_events":0,"start_epoch":%s}\n' "$now_epoch" > "$state"
  fi

  # Resolve token count: use real transcript data when available, fall back to estimation.
  # Transcript gives us the context window size (snapshot); estimation is cumulative.
  local new_tokens=0
  local _use_transcript=false
  if [ "$token_mode" != "output" ]; then
    read_transcript_tokens
    if [ "$_TRANSCRIPT_AVAILABLE" = true ]; then
      _use_transcript=true
    elif [ -n "$tool_input" ]; then
      new_tokens=$(estimate_tokens "$tool_input")
    fi
  else
    # PostToolUse: estimate output tokens from tool result text
    if [ -n "$tool_input" ]; then
      new_tokens=$(estimate_tokens "$tool_input")
    fi
  fi

  # Resolve all budget limits: use pre-extracted _CFG_* values if available (1A),
  # otherwise fall back to jq read
  local max_actions="" timeout_seconds="" max_tokens=""
  local max_input_tokens="" max_output_tokens=""
  local max_total_actions="" max_total_input_tokens="" max_total_output_tokens="" max_total_tokens="" max_total_time=""
  if [ -n "${_CFG_MAX_ACTIONS+x}" ]; then
    max_actions="$_CFG_MAX_ACTIONS"
    timeout_seconds="$_CFG_TIMEOUT_SECONDS"
    max_tokens="$_CFG_MAX_TOKENS"
    max_input_tokens="${_CFG_MAX_INPUT_TOKENS:-}"
    max_output_tokens="${_CFG_MAX_OUTPUT_TOKENS:-}"
    max_total_actions="${_CFG_MAX_TOTAL_ACTIONS:-}"
    max_total_input_tokens="${_CFG_MAX_TOTAL_INPUT_TOKENS:-}"
    max_total_output_tokens="${_CFG_MAX_TOTAL_OUTPUT_TOKENS:-}"
    max_total_tokens="${_CFG_MAX_TOTAL_TOKENS:-}"
    max_total_time="${_CFG_MAX_TOTAL_TIME:-}"
  elif [ -f "$LANEKEEP_CONFIG_FILE" ]; then
    eval "$(jq -r '
      "max_actions=" + (.budget.max_actions // "" | tostring | @sh),
      "timeout_seconds=" + (.budget.timeout_seconds // "" | tostring | @sh),
      "max_tokens=" + (.budget.max_tokens // "" | tostring | @sh),
      "max_input_tokens=" + (.budget.max_input_tokens // "" | tostring | @sh),
      "max_output_tokens=" + (.budget.max_output_tokens // "" | tostring | @sh),
      "max_total_actions=" + (.budget.max_total_actions // "" | tostring | @sh),
      "max_total_input_tokens=" + (.budget.max_total_input_tokens // "" | tostring | @sh),
      "max_total_output_tokens=" + (.budget.max_total_output_tokens // "" | tostring | @sh),
      "max_total_tokens=" + (.budget.max_total_tokens // "" | tostring | @sh),
      "max_total_time=" + (.budget.max_total_time_seconds // "" | tostring | @sh)
    ' "$LANEKEEP_CONFIG_FILE" 2>/dev/null)" || true
  fi
  if [ -n "${LANEKEEP_TASKSPEC_FILE:-}" ] && [ -f "$LANEKEEP_TASKSPEC_FILE" ]; then
    # Fast-path: skip jq for empty/minimal taskspec
    local _ts_sz
    _ts_sz=$(stat -c %s "$LANEKEEP_TASKSPEC_FILE" 2>/dev/null) || _ts_sz=0
    if [ "$_ts_sz" -gt 4 ]; then
      local _ts_ma="" _ts_ts="" _ts_mt="" _ts_mit="" _ts_mot=""
      eval "$(jq -r '
        "_ts_ma=" + (.budget.max_actions // "" | tostring | @sh),
        "_ts_ts=" + (.budget.timeout_seconds // "" | tostring | @sh),
        "_ts_mt=" + (.budget.max_tokens // "" | tostring | @sh),
        "_ts_mit=" + (.budget.max_input_tokens // "" | tostring | @sh),
        "_ts_mot=" + (.budget.max_output_tokens // "" | tostring | @sh)
      ' "$LANEKEEP_TASKSPEC_FILE" 2>/dev/null)" || true
      [ -n "$_ts_ma" ] && max_actions="$_ts_ma"
      [ -n "$_ts_ts" ] && timeout_seconds="$_ts_ts"
      [ -n "$_ts_mt" ] && max_tokens="$_ts_mt"
      [ -n "$_ts_mit" ] && max_input_tokens="$_ts_mit"
      [ -n "$_ts_mot" ] && max_output_tokens="$_ts_mot"
    fi
  fi
  # Layer 3: env var overrides
  [ -n "${LANEKEEP_MAX_ACTIONS:-}" ] && max_actions="$LANEKEEP_MAX_ACTIONS"
  [ -n "${LANEKEEP_TIMEOUT_SECONDS:-}" ] && timeout_seconds="$LANEKEEP_TIMEOUT_SECONDS"
  [ -n "${LANEKEEP_MAX_TOKENS:-}" ] && max_tokens="$LANEKEEP_MAX_TOKENS"
  [ -n "${LANEKEEP_MAX_INPUT_TOKENS:-}" ] && max_input_tokens="$LANEKEEP_MAX_INPUT_TOKENS"
  [ -n "${LANEKEEP_MAX_OUTPUT_TOKENS:-}" ] && max_output_tokens="$LANEKEEP_MAX_OUTPUT_TOKENS"

  # === LOCKED SECTION: read state, check limits, increment, write back ===
  # Acquire lock BEFORE reading state to prevent TOCTOU race
  exec 9>"${state}.lock"
  if ! flock -w 2 9; then
    BUDGET_PASSED=false
    BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5)\nFailed to acquire state lock"
    exec 9>&-
    return 1
  fi

  # Read current state under lock
  local action_count start_epoch token_count total_events session_id input_tokens_st output_tokens_st
  local cache_creation_st cache_read_st
  eval "$(jq -r '
    "action_count=" + (.action_count // 0 | tostring | @sh),
    "start_epoch=" + (.start_epoch // 0 | tostring | @sh),
    "token_count=" + (.token_count // 0 | tostring | @sh),
    "input_tokens_st=" + (.input_tokens // 0 | tostring | @sh),
    "output_tokens_st=" + (.output_tokens // 0 | tostring | @sh),
    "cache_creation_st=" + (.cache_creation_input_tokens // 0 | tostring | @sh),
    "cache_read_st=" + (.cache_read_input_tokens // 0 | tostring | @sh),
    "total_events=" + (.total_events // 0 | tostring | @sh),
    "session_id=" + (.session_id // "" | @sh),
    "_prev_token_source=" + (.token_source // "" | @sh),
    "_prev_model=" + (.model // "" | @sh)
  ' "$state" 2>/dev/null)" || { action_count=0; start_epoch=$now_epoch; token_count=0; input_tokens_st=0; output_tokens_st=0; cache_creation_st=0; cache_read_st=0; total_events=0; session_id=""; _prev_token_source=""; _prev_model=""; }
  # Guard against non-numeric values from corrupted state
  [[ "$action_count" =~ ^[0-9]+$ ]] || action_count=0
  [[ "$start_epoch" =~ ^[0-9]+$ ]] || start_epoch=$now_epoch
  [[ "$token_count" =~ ^[0-9]+$ ]] || token_count=0
  [[ "$input_tokens_st" =~ ^[0-9]+$ ]] || input_tokens_st=0
  [[ "$output_tokens_st" =~ ^[0-9]+$ ]] || output_tokens_st=0
  [[ "$cache_creation_st" =~ ^[0-9]+$ ]] || cache_creation_st=0
  [[ "$cache_read_st" =~ ^[0-9]+$ ]] || cache_read_st=0
  [[ "$total_events" =~ ^[0-9]+$ ]] || total_events=0

  # Session boundary: detect when Claude Code session_id changes
  if [ -n "$cc_session_id" ] && [ "$cc_session_id" != "$session_id" ]; then
    if [ -n "$session_id" ] && [ "$action_count" -gt 0 ]; then
      # Finalize old session into cumulative.json before resetting
      printf '{"action_count":%d,"token_count":%d,"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d,"total_events":%d,"start_epoch":%d,"session_id":"%s"}\n' \
        "$action_count" "$token_count" "$input_tokens_st" "$output_tokens_st" "$cache_creation_st" "$cache_read_st" "$total_events" "$start_epoch" "$session_id" > "${state}.tmp" \
        && mv "${state}.tmp" "$state"
      cumulative_init
      # Reset counters for new session
      action_count=0; token_count=0; input_tokens_st=0; output_tokens_st=0; cache_creation_st=0; cache_read_st=0; total_events=0; start_epoch=$now_epoch
    fi
    session_id="$cc_session_id"
  fi

  # Always increment total_events (tracks all tool calls for UI display)
  total_events=$((total_events + 1))

  # Update counters based on mode and token source
  # skip_increment: when pipeline decision is "ask", don't count the action
  # (it may be denied by the user, preventing phantom budget consumption)
  if [ "$token_mode" = "output" ]; then
    # PostToolUse: track output tokens only (always estimated)
    output_tokens_st=$((output_tokens_st + new_tokens))
    token_count=$((token_count + new_tokens))
  elif [ "$_use_transcript" = true ]; then
    # Transcript mode: input_tokens = context window size (snapshot, not cumulative)
    input_tokens_st=$_TRANSCRIPT_INPUT_TOKENS
    cache_creation_st=$_TRANSCRIPT_CACHE_CREATION_TOKENS
    cache_read_st=$_TRANSCRIPT_CACHE_READ_TOKENS
    token_count=$((input_tokens_st + output_tokens_st))
    if [ "$already_blocked" != "true" ] && [ "$skip_increment" != "true" ]; then
      action_count=$((action_count + 1))
    fi
  else
    # Fallback: cumulative estimation
    input_tokens_st=$((input_tokens_st + new_tokens))
    token_count=$((token_count + new_tokens))
    if [ "$already_blocked" != "true" ] && [ "$skip_increment" != "true" ]; then
      action_count=$((action_count + 1))
    fi
  fi

  # Track elapsed seconds for UI metrics (use cached now_epoch — 1B)
  local elapsed_seconds=$((now_epoch - ${start_epoch%.*}))

  # Write updated state BEFORE limit checks so state is always persisted
  local _token_source="estimate"
  [ "$_use_transcript" = true ] && _token_source="transcript"
  # PostToolUse doesn't read transcript — preserve previous token_source/model
  if [ "$_token_source" = "estimate" ] && [ "${_prev_token_source:-}" = "transcript" ]; then
    _token_source="$_prev_token_source"
  fi
  local _model_field=""
  [ -n "$_TRANSCRIPT_MODEL" ] && _model_field="$(printf ',"model":"%s"' "$_TRANSCRIPT_MODEL")"
  # Preserve model from previous state if transcript wasn't read this time
  if [ -z "$_model_field" ] && [ -n "${_prev_model:-}" ]; then
    _model_field="$(printf ',"model":"%s"' "$_prev_model")"
  fi
  printf '{"action_count":%d,"token_count":%d,"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d,"total_events":%d,"start_epoch":%d,"elapsed_seconds":%d,"session_id":"%s","token_source":"%s"%s}\n' \
    "$action_count" "$token_count" "$input_tokens_st" "$output_tokens_st" "$cache_creation_st" "$cache_read_st" "$total_events" "$start_epoch" "$elapsed_seconds" "$session_id" "$_token_source" "$_model_field" > "${state}.tmp" \
    && mv "${state}.tmp" "$state"
  exec 9>&-

  # Skip limit enforcement when already blocked by earlier tier
  if [ "$already_blocked" = "true" ]; then
    BUDGET_REASON="Within budget (tracking only)"
    return 0
  fi

  # When skip_increment is true (ask decision), action_count wasn't bumped
  # but input_tokens/token_count already include new_tokens, so only
  # adjust the action check
  local _check_actions=$action_count
  local _check_tokens=$token_count
  local _check_input=$input_tokens_st
  if [ "$skip_increment" = "true" ]; then
    _check_actions=$((_check_actions + 1))
  fi

  # Check action count
  if [ -n "$max_actions" ] && [ "$max_actions" != "null" ]; then
    if [ "$_check_actions" -gt "$max_actions" ]; then
      BUDGET_PASSED=false
      BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAction budget exceeded: ${_check_actions}/${max_actions}"
      return 1
    fi
  fi

  # Check token count
  if [ -n "$max_tokens" ] && [ "$max_tokens" != "null" ]; then
    if [ "$_check_tokens" -gt "$max_tokens" ]; then
      BUDGET_PASSED=false
      BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nToken budget exceeded: ${_check_tokens}/${max_tokens}"
      return 1
    fi
  fi

  # Check input token limit
  if [ -n "$max_input_tokens" ] && [ "$max_input_tokens" != "null" ]; then
    if [ "$_check_input" -gt "$max_input_tokens" ]; then
      BUDGET_PASSED=false
      BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nInput token budget exceeded: ${_check_input}/${max_input_tokens}"
      return 1
    fi
  fi

  # Check output token limit
  if [ -n "$max_output_tokens" ] && [ "$max_output_tokens" != "null" ]; then
    if [ "$output_tokens_st" -gt "$max_output_tokens" ]; then
      BUDGET_PASSED=false
      BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nOutput token budget exceeded: ${output_tokens_st}/${max_output_tokens}"
      return 1
    fi
  fi

  # Check wall-clock time (use cached now_epoch — 1B)
  if [ -n "$timeout_seconds" ] && [ "$timeout_seconds" != "null" ]; then
    local elapsed
    elapsed=$((now_epoch - ${start_epoch%.*}))
    if [ "$elapsed" -gt "$timeout_seconds" ]; then
      BUDGET_PASSED=false
      BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nTime budget exceeded: ${elapsed}s/${timeout_seconds}s"
      return 1
    fi
  fi

  # === ALL-TIME CUMULATIVE LIMIT CHECKS ===
  # Env var overrides (max_total_* already read from config above)
  [ -n "${LANEKEEP_MAX_TOTAL_ACTIONS:-}" ] && max_total_actions="$LANEKEEP_MAX_TOTAL_ACTIONS"
  [ -n "${LANEKEEP_MAX_TOTAL_INPUT_TOKENS:-}" ] && max_total_input_tokens="$LANEKEEP_MAX_TOTAL_INPUT_TOKENS"
  [ -n "${LANEKEEP_MAX_TOTAL_OUTPUT_TOKENS:-}" ] && max_total_output_tokens="$LANEKEEP_MAX_TOTAL_OUTPUT_TOKENS"
  [ -n "${LANEKEEP_MAX_TOTAL_TOKENS:-}" ] && max_total_tokens="$LANEKEEP_MAX_TOTAL_TOKENS"
  [ -n "${LANEKEEP_MAX_TOTAL_TIME:-}" ] && max_total_time="$LANEKEEP_MAX_TOTAL_TIME"

  # Skip if no all-time limits configured
  if { [ -n "$max_total_actions" ] && [ "$max_total_actions" != "null" ]; } \
     || { [ -n "$max_total_input_tokens" ] && [ "$max_total_input_tokens" != "null" ]; } \
     || { [ -n "$max_total_output_tokens" ] && [ "$max_total_output_tokens" != "null" ]; } \
     || { [ -n "$max_total_tokens" ] && [ "$max_total_tokens" != "null" ]; } \
     || { [ -n "$max_total_time" ] && [ "$max_total_time" != "null" ]; }; then

    local cumfile="${LANEKEEP_CUMULATIVE_FILE:-${PROJECT_DIR:-.}/.lanekeep/cumulative.json}"
    if [ -f "$cumfile" ]; then
      local cum_actions=0 cum_input_tokens=0 cum_output_tokens=0 cum_tokens=0 cum_time=0
      eval "$(jq -r '
        "cum_actions=" + (.total_actions // 0 | tostring | @sh),
        "cum_input_tokens=" + (.total_input_tokens // 0 | tostring | @sh),
        "cum_output_tokens=" + (.total_output_tokens // 0 | tostring | @sh),
        "cum_tokens=" + (.total_tokens // 0 | tostring | @sh),
        "cum_time=" + (.total_time_seconds // 0 | tostring | @sh)
      ' "$cumfile" 2>/dev/null)" || true
      [[ "$cum_actions" =~ ^[0-9]+$ ]] || cum_actions=0
      [[ "$cum_input_tokens" =~ ^[0-9]+$ ]] || cum_input_tokens=0
      [[ "$cum_output_tokens" =~ ^[0-9]+$ ]] || cum_output_tokens=0
      [[ "$cum_tokens" =~ ^[0-9]+$ ]] || cum_tokens=0
      [[ "$cum_time" =~ ^[0-9]+$ ]] || cum_time=0

      # Add current session counters (use check values for limit enforcement)
      local total_actions=$((cum_actions + _check_actions))
      local total_input_toks=$((cum_input_tokens + _check_input))
      local total_output_toks=$((cum_output_tokens + output_tokens_st))
      local total_tokens=$((cum_tokens + _check_tokens))
      local total_time=$((cum_time + elapsed_seconds))

      # Check all-time action limit
      if [ -n "$max_total_actions" ] && [ "$max_total_actions" != "null" ]; then
        if [ "$total_actions" -gt "$max_total_actions" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time action budget exceeded: ${total_actions}/${max_total_actions}"
          return 1
        fi
      fi

      # Check all-time input token limit
      if [ -n "$max_total_input_tokens" ] && [ "$max_total_input_tokens" != "null" ]; then
        if [ "$total_input_toks" -gt "$max_total_input_tokens" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time input token budget exceeded: ${total_input_toks}/${max_total_input_tokens}"
          return 1
        fi
      fi

      # Check all-time output token limit
      if [ -n "$max_total_output_tokens" ] && [ "$max_total_output_tokens" != "null" ]; then
        if [ "$total_output_toks" -gt "$max_total_output_tokens" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time output token budget exceeded: ${total_output_toks}/${max_total_output_tokens}"
          return 1
        fi
      fi

      # Check all-time token limit
      if [ -n "$max_total_tokens" ] && [ "$max_total_tokens" != "null" ]; then
        if [ "$total_tokens" -gt "$max_total_tokens" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time token budget exceeded: ${total_tokens}/${max_total_tokens}"
          return 1
        fi
      fi

      # Check all-time time limit
      if [ -n "$max_total_time" ] && [ "$max_total_time" != "null" ]; then
        if [ "$total_time" -gt "$max_total_time" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time time budget exceeded: ${total_time}s/${max_total_time}s"
          return 1
        fi
      fi
    fi
  fi

  return 0
}
