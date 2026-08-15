#!/usr/bin/env bash
# shellcheck disable=SC2034  # BUDGET_PASSED, BUDGET_REASON set here, read externally via indirection
# Tier 5: Budget tracking (action count, wall-clock time, token tracking)

BUDGET_PASSED=true
BUDGET_REASON=""
BUDGET_HINT=""
# Set to "true" when budget_eval returns 1 because a CUMULATIVE (lifetime)
# cap tripped, so the handler can forward the signal into the trace event.
# Per-session denials leave this empty.
BUDGET_CUMULATIVE_HALTED=""

# Define _json_escape if not already available (e.g., when sourced standalone in tests)
if ! type _json_escape &>/dev/null; then
  _json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
  }
fi

# Emit a stop signal when a CUMULATIVE (lifetime) budget cap trips.
# Writes a sibling file next to cumulative.json that loopers/orchestrators
# can poll to decide whether to spawn the next iteration.
# Per-session caps do NOT emit a halt — they reset on session boundary.
_budget_emit_halt() {
  local reason="$1"
  local cumfile="${LANEKEEP_CUMULATIVE_FILE:-${PROJECT_DIR:-.}/.lanekeep/cumulative.json}"
  local halted_file="${LANEKEEP_HALTED_FILE:-$(dirname "$cumfile")/halted.json}"
  (umask 077; mkdir -p "$(dirname "$halted_file")" 2>/dev/null) || return 0
  printf '{"halted":true,"halted_at":"%s","reason":"%s","correlation_id":"%s","lanekeep_session_id":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(_json_escape "$reason")" \
    "$(_json_escape "${LANEKEEP_CORRELATION_ID:-}")" \
    "$(_json_escape "${LANEKEEP_SESSION_ID:-}")" \
    > "${halted_file}.tmp" 2>/dev/null && mv "${halted_file}.tmp" "$halted_file" 2>/dev/null
}

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
  if [ -L "$path" ]; then
    echo "[LaneKeep] BudgetEvaluator: rejecting symlink transcript path" >&2
    return 0
  fi

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
  BUDGET_HINT=""
  BUDGET_CUMULATIVE_HALTED=""

  local state="$LANEKEEP_STATE_FILE"
  local tool_input="${1:-}"
  local now_epoch="${2:-$(date +%s)}"
  local already_blocked="${3:-}"
  local token_mode="${4:-input}"
  local cc_session_id="${5:-}"
  local skip_increment="${6:-false}"  # skip counter increment (for "ask" decisions)

  # Initialize state file if missing
  if [ ! -f "$state" ]; then
    printf '{"action_count":0,"token_count":0,"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"total_events":0,"start_epoch":%s,"lanekeep_session_id":"%s"}\n' "$now_epoch" "$(_json_escape "${LANEKEEP_SESSION_ID:-}")" > "$state"
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
  local max_cost="" max_total_cost=""
  local max_task_actions="" max_task_input_tokens="" max_task_output_tokens="" max_task_tokens="" max_task_time="" max_task_cost=""
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
    max_cost="${_CFG_MAX_COST:-}"
    max_total_cost="${_CFG_MAX_TOTAL_COST:-}"
    max_task_actions="${_CFG_MAX_TASK_ACTIONS:-}"
    max_task_input_tokens="${_CFG_MAX_TASK_INPUT_TOKENS:-}"
    max_task_output_tokens="${_CFG_MAX_TASK_OUTPUT_TOKENS:-}"
    max_task_tokens="${_CFG_MAX_TASK_TOKENS:-}"
    max_task_time="${_CFG_MAX_TASK_TIME:-}"
    max_task_cost="${_CFG_MAX_TASK_COST:-}"
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
      "max_total_time=" + (.budget.max_total_time_seconds // "" | tostring | @sh),
      "max_cost=" + (.budget.max_cost // "" | tostring | @sh),
      "max_total_cost=" + (.budget.max_total_cost // "" | tostring | @sh),
      "max_task_actions=" + (.budget.max_task_actions // "" | tostring | @sh),
      "max_task_input_tokens=" + (.budget.max_task_input_tokens // "" | tostring | @sh),
      "max_task_output_tokens=" + (.budget.max_task_output_tokens // "" | tostring | @sh),
      "max_task_tokens=" + (.budget.max_task_tokens // "" | tostring | @sh),
      "max_task_time=" + (.budget.max_task_time_seconds // "" | tostring | @sh),
      "max_task_cost=" + (.budget.max_task_cost // "" | tostring | @sh)
    ' "$LANEKEEP_CONFIG_FILE" 2>/dev/null)" || true
  fi
  if [ -n "${LANEKEEP_TASKSPEC_FILE:-}" ] && [ -f "$LANEKEEP_TASKSPEC_FILE" ]; then
    # Fast-path: skip jq for empty/minimal taskspec
    local _ts_sz
    _ts_sz=$(stat -c %s "$LANEKEEP_TASKSPEC_FILE" 2>/dev/null) || _ts_sz=0
    if [ "$_ts_sz" -gt 4 ]; then
      local _ts_ma="" _ts_ts="" _ts_mt="" _ts_mit="" _ts_mot="" _ts_mc=""
      local _ts_tka="" _ts_tkit="" _ts_tkot="" _ts_tkt="" _ts_tktt="" _ts_tkc=""
      eval "$(jq -r '
        "_ts_ma=" + (.budget.max_actions // "" | tostring | @sh),
        "_ts_ts=" + (.budget.timeout_seconds // "" | tostring | @sh),
        "_ts_mt=" + (.budget.max_tokens // "" | tostring | @sh),
        "_ts_mit=" + (.budget.max_input_tokens // "" | tostring | @sh),
        "_ts_mot=" + (.budget.max_output_tokens // "" | tostring | @sh),
        "_ts_mc=" + (.budget.max_cost // "" | tostring | @sh),
        "_ts_tka=" + (.budget.max_task_actions // "" | tostring | @sh),
        "_ts_tkit=" + (.budget.max_task_input_tokens // "" | tostring | @sh),
        "_ts_tkot=" + (.budget.max_task_output_tokens // "" | tostring | @sh),
        "_ts_tkt=" + (.budget.max_task_tokens // "" | tostring | @sh),
        "_ts_tktt=" + (.budget.max_task_time_seconds // "" | tostring | @sh),
        "_ts_tkc=" + (.budget.max_task_cost // "" | tostring | @sh)
      ' "$LANEKEEP_TASKSPEC_FILE" 2>/dev/null)" || true
      [ -n "$_ts_ma" ] && max_actions="$_ts_ma"
      [ -n "$_ts_ts" ] && timeout_seconds="$_ts_ts"
      [ -n "$_ts_mt" ] && max_tokens="$_ts_mt"
      [ -n "$_ts_mit" ] && max_input_tokens="$_ts_mit"
      [ -n "$_ts_mot" ] && max_output_tokens="$_ts_mot"
      [ -n "$_ts_mc" ] && max_cost="$_ts_mc"
      [ -n "$_ts_tka" ] && max_task_actions="$_ts_tka"
      [ -n "$_ts_tkit" ] && max_task_input_tokens="$_ts_tkit"
      [ -n "$_ts_tkot" ] && max_task_output_tokens="$_ts_tkot"
      [ -n "$_ts_tkt" ] && max_task_tokens="$_ts_tkt"
      [ -n "$_ts_tktt" ] && max_task_time="$_ts_tktt"
      [ -n "$_ts_tkc" ] && max_task_cost="$_ts_tkc"
    fi
  fi
  # Layer 3: env var overrides
  [ -n "${LANEKEEP_MAX_ACTIONS:-}" ] && max_actions="$LANEKEEP_MAX_ACTIONS"
  [ -n "${LANEKEEP_TIMEOUT_SECONDS:-}" ] && timeout_seconds="$LANEKEEP_TIMEOUT_SECONDS"
  [ -n "${LANEKEEP_MAX_TOKENS:-}" ] && max_tokens="$LANEKEEP_MAX_TOKENS"
  [ -n "${LANEKEEP_MAX_INPUT_TOKENS:-}" ] && max_input_tokens="$LANEKEEP_MAX_INPUT_TOKENS"
  [ -n "${LANEKEEP_MAX_OUTPUT_TOKENS:-}" ] && max_output_tokens="$LANEKEEP_MAX_OUTPUT_TOKENS"
  [ -n "${LANEKEEP_MAX_COST:-}" ] && max_cost="$LANEKEEP_MAX_COST"
  [ -n "${LANEKEEP_MAX_TOTAL_COST:-}" ] && max_total_cost="$LANEKEEP_MAX_TOTAL_COST"
  [ -n "${LANEKEEP_MAX_TASK_ACTIONS:-}" ] && max_task_actions="$LANEKEEP_MAX_TASK_ACTIONS"
  [ -n "${LANEKEEP_MAX_TASK_INPUT_TOKENS:-}" ] && max_task_input_tokens="$LANEKEEP_MAX_TASK_INPUT_TOKENS"
  [ -n "${LANEKEEP_MAX_TASK_OUTPUT_TOKENS:-}" ] && max_task_output_tokens="$LANEKEEP_MAX_TASK_OUTPUT_TOKENS"
  [ -n "${LANEKEEP_MAX_TASK_TOKENS:-}" ] && max_task_tokens="$LANEKEEP_MAX_TASK_TOKENS"
  [ -n "${LANEKEEP_MAX_TASK_TIME_SECONDS:-}" ] && max_task_time="$LANEKEEP_MAX_TASK_TIME_SECONDS"
  [ -n "${LANEKEEP_MAX_TASK_COST:-}" ] && max_task_cost="$LANEKEEP_MAX_TASK_COST"

  # === LOCKED SECTION: read state, check limits, increment, write back ===
  # Acquire lock BEFORE reading state to prevent TOCTOU race
  exec 9>"${state}.lock"
  if ! flock -w 2 9; then
    BUDGET_PASSED=false
    BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5)\nFailed to acquire state lock"
    BUDGET_HINT="DENIED: Budget state contention. Retry the request shortly."
    exec 9>&-
    return 1
  fi

  # Read current state under lock
  local action_count start_epoch token_count total_events session_id input_tokens_st output_tokens_st
  local cache_creation_st cache_read_st
  local task_id task_action_count task_input_tokens_st task_output_tokens_st task_token_count task_start_epoch
  eval "$(jq -r '
    "action_count=" + (.action_count // 0 | tostring | @sh),
    "warn_count=" + (.warn_count // 0 | tostring | @sh),
    "ask_count=" + (.ask_count // 0 | tostring | @sh),
    "start_epoch=" + (.start_epoch // 0 | tostring | @sh),
    "token_count=" + (.token_count // 0 | tostring | @sh),
    "input_tokens_st=" + (.input_tokens // 0 | tostring | @sh),
    "output_tokens_st=" + (.output_tokens // 0 | tostring | @sh),
    "cache_creation_st=" + (.cache_creation_input_tokens // 0 | tostring | @sh),
    "cache_read_st=" + (.cache_read_input_tokens // 0 | tostring | @sh),
    "total_events=" + (.total_events // 0 | tostring | @sh),
    "session_id=" + (.session_id // "" | @sh),
    "task_id=" + (.task_id // "" | @sh),
    "task_action_count=" + (.task_action_count // 0 | tostring | @sh),
    "task_input_tokens_st=" + (.task_input_tokens // 0 | tostring | @sh),
    "task_output_tokens_st=" + (.task_output_tokens // 0 | tostring | @sh),
    "task_token_count=" + (.task_token_count // 0 | tostring | @sh),
    "task_start_epoch=" + (.task_start_epoch // 0 | tostring | @sh),
    "_prev_token_source=" + (.token_source // "" | @sh),
    "_prev_model=" + (.model // "" | @sh)
  ' "$state" 2>/dev/null)" || { action_count=0; start_epoch=$now_epoch; token_count=0; input_tokens_st=0; output_tokens_st=0; cache_creation_st=0; cache_read_st=0; total_events=0; session_id=""; task_id=""; task_action_count=0; task_input_tokens_st=0; task_output_tokens_st=0; task_token_count=0; task_start_epoch=$now_epoch; _prev_token_source=""; _prev_model=""; }

  # AG-005: hydrate per-agent bucket for the current agent (if tagged).
  # Buckets are keyed by _TRACE_AGENT_ID; untagged sessions skip this entirely.
  local agt_actions=0 agt_input=0 agt_output=0 agt_tokens=0 agt_events=0
  local agt_ccr=0 agt_crd=0 agt_start=0
  if [ -n "${_TRACE_AGENT_ID:-}" ]; then
    eval "$(jq -r --arg aid "$_TRACE_AGENT_ID" '
      (.per_agent[$aid] // {}) as $b |
      "agt_actions=" + ($b.action_count // 0 | tostring | @sh),
      "agt_input=" + ($b.input_tokens // 0 | tostring | @sh),
      "agt_output=" + ($b.output_tokens // 0 | tostring | @sh),
      "agt_tokens=" + ($b.token_count // 0 | tostring | @sh),
      "agt_events=" + ($b.total_events // 0 | tostring | @sh),
      "agt_ccr=" + ($b.cache_creation_input_tokens // 0 | tostring | @sh),
      "agt_crd=" + ($b.cache_read_input_tokens // 0 | tostring | @sh),
      "agt_start=" + ($b.start_epoch // 0 | tostring | @sh)
    ' "$state" 2>/dev/null)" || true
    [[ "$agt_actions" =~ ^[0-9]+$ ]] || agt_actions=0
    [[ "$agt_input" =~ ^[0-9]+$ ]] || agt_input=0
    [[ "$agt_output" =~ ^[0-9]+$ ]] || agt_output=0
    [[ "$agt_tokens" =~ ^[0-9]+$ ]] || agt_tokens=0
    [[ "$agt_events" =~ ^[0-9]+$ ]] || agt_events=0
    [[ "$agt_ccr" =~ ^[0-9]+$ ]] || agt_ccr=0
    [[ "$agt_crd" =~ ^[0-9]+$ ]] || agt_crd=0
    [[ "$agt_start" =~ ^[0-9]+$ ]] || agt_start=0
    [ "$agt_start" -eq 0 ] && agt_start=$now_epoch
  fi
  # Guard against non-numeric values from corrupted state
  [[ "$action_count" =~ ^[0-9]+$ ]] || action_count=0
  # Expose pre-increment session action count to downstream evaluators
  # (Tier 5.5 context-budget action-count signal, and any others that need it).
  _SESSION_ACTION_COUNT="$action_count"
  # Expose cumulative warn/ask counts for feat-cumulative-risk-scoring.
  [[ "$warn_count" =~ ^[0-9]+$ ]] || warn_count=0
  [[ "$ask_count" =~ ^[0-9]+$ ]] || ask_count=0
  _SESSION_WARN_COUNT="$warn_count"
  _SESSION_ASK_COUNT="$ask_count"
  [[ "$start_epoch" =~ ^[0-9]+$ ]] || start_epoch=$now_epoch
  [[ "$token_count" =~ ^[0-9]+$ ]] || token_count=0
  [[ "$input_tokens_st" =~ ^[0-9]+$ ]] || input_tokens_st=0
  [[ "$output_tokens_st" =~ ^[0-9]+$ ]] || output_tokens_st=0
  [[ "$cache_creation_st" =~ ^[0-9]+$ ]] || cache_creation_st=0
  [[ "$cache_read_st" =~ ^[0-9]+$ ]] || cache_read_st=0
  [[ "$total_events" =~ ^[0-9]+$ ]] || total_events=0
  [[ "$task_action_count" =~ ^[0-9]+$ ]] || task_action_count=0
  [[ "$task_input_tokens_st" =~ ^[0-9]+$ ]] || task_input_tokens_st=0
  [[ "$task_output_tokens_st" =~ ^[0-9]+$ ]] || task_output_tokens_st=0
  [[ "$task_token_count" =~ ^[0-9]+$ ]] || task_token_count=0
  [[ "$task_start_epoch" =~ ^[0-9]+$ ]] || task_start_epoch=$now_epoch

  # Session boundary: detect when Claude Code session_id changes
  if [ -n "$cc_session_id" ] && [ "$cc_session_id" != "$session_id" ]; then
    if [ -n "$session_id" ] && [ "$action_count" -gt 0 ]; then
      # AG-006: capture per_agent block BEFORE we overwrite state.json so we can
      # re-attach it and let cumulative_init fold each bucket into its lifetime totals.
      local _prev_per_agent=""
      _prev_per_agent=$(jq -c '.per_agent // empty' "$state" 2>/dev/null) || _prev_per_agent=""
      # Finalize old session into cumulative.json before resetting
      local _sb_model=""
      [ -n "${_prev_model:-}" ] && _sb_model="$(printf ',"model":"%s"' "$(_json_escape "$_prev_model")")"
      printf '{"action_count":%d,"token_count":%d,"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d,"total_events":%d,"start_epoch":%d,"session_id":"%s","lanekeep_session_id":"%s"%s}\n' \
        "$action_count" "$token_count" "$input_tokens_st" "$output_tokens_st" "$cache_creation_st" "$cache_read_st" "$total_events" "$start_epoch" "$(_json_escape "$session_id")" "$(_json_escape "${LANEKEEP_SESSION_ID:-}")" "$_sb_model" > "${state}.tmp" \
        && mv "${state}.tmp" "$state"
      if [ -n "$_prev_per_agent" ]; then
        local _sb_merged
        _sb_merged=$(jq -c --argjson pa "$_prev_per_agent" '. + {per_agent: $pa}' "$state" 2>/dev/null) \
          && printf '%s\n' "$_sb_merged" > "${state}.tmp" \
          && mv "${state}.tmp" "$state"
      fi
      cumulative_init
      # Reset counters for new session (incl. cumulative-risk warn/ask counters)
      action_count=0; token_count=0; input_tokens_st=0; output_tokens_st=0; cache_creation_st=0; cache_read_st=0; total_events=0; start_epoch=$now_epoch
      warn_count=0; ask_count=0
      _SESSION_WARN_COUNT=0; _SESSION_ASK_COUNT=0
      # AG-005: per-agent buckets are session-scoped; reset to zero on boundary.
      agt_actions=0; agt_input=0; agt_output=0; agt_tokens=0; agt_events=0
      agt_ccr=0; agt_crd=0; agt_start=$now_epoch
    fi
    session_id="$cc_session_id"
  fi

  # Task boundary: when LANEKEEP_TASK_ID env var changes, reset task counters.
  # Independent of session boundary — a task may span sessions or vice versa.
  # If LANEKEEP_TASK_ID is unset, no boundary detection or enforcement runs.
  local _env_task_id="${LANEKEEP_TASK_ID:-}"
  if [ -n "$_env_task_id" ] && [ "$_env_task_id" != "$task_id" ]; then
    task_action_count=0
    task_input_tokens_st=0
    task_output_tokens_st=0
    task_token_count=0
    task_start_epoch=$now_epoch
    task_id="$_env_task_id"
  fi

  # Always increment total_events (tracks all tool calls for UI display)
  total_events=$((total_events + 1))
  # AG-005: mirror per-agent event count when tagged.
  [ -n "${_TRACE_AGENT_ID:-}" ] && agt_events=$((agt_events + 1))

  # Update counters based on mode and token source
  # skip_increment: when pipeline decision is "ask", don't count the action
  # (it may be denied by the user, preventing phantom budget consumption)
  # Per-task counter updates are gated on LANEKEEP_TASK_ID being set, so the
  # task_* fields stay at zero when the scope is unused — keeping state clean
  # for tools that surface budget info and avoiding misleading growing counters.
  local _task_scope_active=false
  [ -n "${LANEKEEP_TASK_ID:-}" ] && _task_scope_active=true

  if [ "$token_mode" = "output" ]; then
    # PostToolUse: track output tokens only (always estimated)
    output_tokens_st=$((output_tokens_st + new_tokens))
    token_count=$((token_count + new_tokens))
    if [ "$_task_scope_active" = true ]; then
      task_output_tokens_st=$((task_output_tokens_st + new_tokens))
      task_token_count=$((task_token_count + new_tokens))
    fi
    # AG-005: mirror per-agent output-side updates.
    if [ -n "${_TRACE_AGENT_ID:-}" ]; then
      agt_output=$((agt_output + new_tokens))
      agt_tokens=$((agt_tokens + new_tokens))
    fi
  elif [ "$_use_transcript" = true ]; then
    # Transcript mode: input_tokens = context window size (snapshot, not cumulative).
    # Task-scoped input mirrors session input — the transcript reflects the live
    # context window, which by definition is bounded by the current invocation.
    input_tokens_st=$_TRANSCRIPT_INPUT_TOKENS
    cache_creation_st=$_TRANSCRIPT_CACHE_CREATION_TOKENS
    cache_read_st=$_TRANSCRIPT_CACHE_READ_TOKENS
    token_count=$((input_tokens_st + output_tokens_st))
    if [ "$_task_scope_active" = true ]; then
      task_input_tokens_st=$_TRANSCRIPT_INPUT_TOKENS
      task_token_count=$((task_input_tokens_st + task_output_tokens_st))
    fi
    if [ "$already_blocked" != "true" ] && [ "$skip_increment" != "true" ]; then
      action_count=$((action_count + 1))
      [ "$_task_scope_active" = true ] && task_action_count=$((task_action_count + 1))
    fi
    # AG-005: mirror per-agent transcript-mode updates.
    if [ -n "${_TRACE_AGENT_ID:-}" ]; then
      agt_input=$_TRANSCRIPT_INPUT_TOKENS
      agt_ccr=$_TRANSCRIPT_CACHE_CREATION_TOKENS
      agt_crd=$_TRANSCRIPT_CACHE_READ_TOKENS
      agt_tokens=$((agt_input + agt_output))
      if [ "$already_blocked" != "true" ] && [ "$skip_increment" != "true" ]; then
        agt_actions=$((agt_actions + 1))
      fi
    fi
  else
    # Fallback: cumulative estimation
    input_tokens_st=$((input_tokens_st + new_tokens))
    token_count=$((token_count + new_tokens))
    if [ "$_task_scope_active" = true ]; then
      task_input_tokens_st=$((task_input_tokens_st + new_tokens))
      task_token_count=$((task_token_count + new_tokens))
    fi
    if [ "$already_blocked" != "true" ] && [ "$skip_increment" != "true" ]; then
      action_count=$((action_count + 1))
      [ "$_task_scope_active" = true ] && task_action_count=$((task_action_count + 1))
    fi
    # AG-005: mirror per-agent estimation-mode updates.
    if [ -n "${_TRACE_AGENT_ID:-}" ]; then
      agt_input=$((agt_input + new_tokens))
      agt_tokens=$((agt_tokens + new_tokens))
      if [ "$already_blocked" != "true" ] && [ "$skip_increment" != "true" ]; then
        agt_actions=$((agt_actions + 1))
      fi
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
  [ -n "$_TRANSCRIPT_MODEL" ] && _model_field="$(printf ',"model":"%s"' "$(_json_escape "$_TRANSCRIPT_MODEL")")"
  # Preserve model from previous state if transcript wasn't read this time
  if [ -z "$_model_field" ] && [ -n "${_prev_model:-}" ]; then
    _model_field="$(printf ',"model":"%s"' "$(_json_escape "$_prev_model")")"
  fi
  # AG-005: capture existing per_agent block before the printf overwrites state.
  # Every write (tagged or not) preserves the block so untagged calls in a mixed
  # session don't wipe other agents' buckets. Reads happen under the same flock
  # we hold, so no other writer can race.
  local _pa_existing=""
  _pa_existing=$(jq -c '.per_agent // empty' "$state" 2>/dev/null) || _pa_existing=""
  printf '{"action_count":%d,"token_count":%d,"input_tokens":%d,"output_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d,"total_events":%d,"warn_count":%d,"ask_count":%d,"start_epoch":%d,"elapsed_seconds":%d,"session_id":"%s","lanekeep_session_id":"%s","token_source":"%s","task_id":"%s","task_action_count":%d,"task_input_tokens":%d,"task_output_tokens":%d,"task_token_count":%d,"task_start_epoch":%d%s}\n' \
    "$action_count" "$token_count" "$input_tokens_st" "$output_tokens_st" "$cache_creation_st" "$cache_read_st" "$total_events" "$warn_count" "$ask_count" "$start_epoch" "$elapsed_seconds" "$(_json_escape "$session_id")" "$(_json_escape "${LANEKEEP_SESSION_ID:-}")" "$_token_source" "$(_json_escape "$task_id")" "$task_action_count" "$task_input_tokens_st" "$task_output_tokens_st" "$task_token_count" "$task_start_epoch" "$_model_field" > "${state}.tmp" \
    && mv "${state}.tmp" "$state"
  # AG-005: merge current agent bucket into per_agent map (lazy — only when tagged).
  # Preserves other agents' buckets by starting from the previously-read map.
  if [ -n "${_TRACE_AGENT_ID:-}" ]; then
    local _pa_base="${_pa_existing:-{\}}"
    local _pa_merged
    _pa_merged=$(jq -c \
      --argjson pa "$_pa_base" \
      --arg aid "$_TRACE_AGENT_ID" \
      --argjson ac "$agt_actions" \
      --argjson it "$agt_input" \
      --argjson ot "$agt_output" \
      --argjson tc "$agt_tokens" \
      --argjson ev "$agt_events" \
      --argjson cc "$agt_ccr" \
      --argjson cr "$agt_crd" \
      --argjson st "$agt_start" \
      --argjson ls "$now_epoch" '
      . + {per_agent: ($pa + {($aid): {
        action_count: $ac,
        input_tokens: $it,
        output_tokens: $ot,
        token_count: $tc,
        total_events: $ev,
        cache_creation_input_tokens: $cc,
        cache_read_input_tokens: $cr,
        start_epoch: $st,
        last_seen_epoch: $ls
      }})}
    ' "$state" 2>/dev/null) \
      && printf '%s\n' "$_pa_merged" > "${state}.tmp" \
      && mv "${state}.tmp" "$state"
  elif [ -n "$_pa_existing" ]; then
    # Untagged write in a session that already has tagged buckets: re-attach
    # the block so mixed sessions preserve per-agent state across untagged calls.
    local _pa_reattach
    _pa_reattach=$(jq -c --argjson pa "$_pa_existing" '. + {per_agent: $pa}' "$state" 2>/dev/null) \
      && printf '%s\n' "$_pa_reattach" > "${state}.tmp" \
      && mv "${state}.tmp" "$state"
  fi
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
      BUDGET_HINT="DENIED: Session action limit (${max_actions}) reached. Stop and report results."
      return 1
    fi
  fi

  # Check token count
  if [ -n "$max_tokens" ] && [ "$max_tokens" != "null" ]; then
    if [ "$_check_tokens" -gt "$max_tokens" ]; then
      BUDGET_PASSED=false
      BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nToken budget exceeded: ${_check_tokens}/${max_tokens}"
      BUDGET_HINT="DENIED: Session token limit (${max_tokens}) reached. Stop and report results."
      return 1
    fi
  fi

  # Check input token limit
  if [ -n "$max_input_tokens" ] && [ "$max_input_tokens" != "null" ]; then
    if [ "$_check_input" -gt "$max_input_tokens" ]; then
      BUDGET_PASSED=false
      BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nInput token budget exceeded: ${_check_input}/${max_input_tokens}"
      BUDGET_HINT="DENIED: Session input token limit (${max_input_tokens}) reached. Stop and report results."
      return 1
    fi
  fi

  # Check output token limit
  if [ -n "$max_output_tokens" ] && [ "$max_output_tokens" != "null" ]; then
    if [ "$output_tokens_st" -gt "$max_output_tokens" ]; then
      BUDGET_PASSED=false
      BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nOutput token budget exceeded: ${output_tokens_st}/${max_output_tokens}"
      BUDGET_HINT="DENIED: Session output token limit (${max_output_tokens}) reached. Stop and report results."
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
      local _mins=$(( timeout_seconds / 60 ))
      [ "$_mins" -lt 1 ] && _mins=1
      BUDGET_HINT="DENIED: Session time limit (${_mins}min) reached. Stop and report results."
      return 1
    fi
  fi

  # Check session cost limit
  local _session_cost=""
  if { [ -n "$max_cost" ] && [ "$max_cost" != "null" ]; } \
     || { [ -n "$max_total_cost" ] && [ "$max_total_cost" != "null" ]; }; then
    # Compute live session cost from current token counts + pricing table
    local _cost_model="${_TRANSCRIPT_MODEL:-${_prev_model:-}}"
    local _pricing_file="${LANEKEEP_DIR:-}/data/pricing.json"
    if [ -n "$_cost_model" ] && [ -f "$_pricing_file" ]; then
      local _cost_ovr='{}'
      if [ -f "$LANEKEEP_CONFIG_FILE" ]; then
        _cost_ovr=$(jq -c '.budget.pricing_overrides // {}' "$LANEKEEP_CONFIG_FILE" 2>/dev/null) || _cost_ovr='{}'
      fi
      _session_cost=$(jq -r --arg model "$_cost_model" \
        --argjson itoks "$_check_input" \
        --argjson cctoks "$cache_creation_st" \
        --argjson crtoks "$cache_read_st" \
        --argjson otoks "$output_tokens_st" \
        --argjson overrides "$_cost_ovr" '
        ((.models[$model] // .models[($model | gsub("-[0-9]{8}$";""))]) // {}) as $base |
        (($overrides[$model] // $overrides[($model | gsub("-[0-9]{8}$";""))]) // {}) as $ovr |
        ($base + $ovr) as $p |
        if ($p | has("input_per_mtok")) then
          ((([0, ($itoks - $cctoks - $crtoks)] | max) * $p.input_per_mtok
            + $cctoks * $p.cache_write_per_mtok
            + $crtoks * $p.cache_read_per_mtok
            + $otoks * $p.output_per_mtok) / 1000000) |
          . * 1000000 | round / 1000000
        else 0 end
      ' "$_pricing_file" 2>/dev/null) || _session_cost=""
    fi

    if [ -n "$_session_cost" ] && [ "$_session_cost" != "0" ]; then
      if [ -n "$max_cost" ] && [ "$max_cost" != "null" ]; then
        # Compare using jq (bash can't do float comparison)
        if jq -e --argjson cost "$_session_cost" --argjson max "$max_cost" \
          'if $cost > $max then true else false end' <<< 'null' >/dev/null 2>&1; then
          local _display_cost
          _display_cost=$(jq -n --argjson v "$_session_cost" '$v * 100 | round / 100')
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nSession cost budget exceeded: \$${_display_cost}/\$${max_cost}"
          BUDGET_HINT="DENIED: Session cost limit (\$${max_cost}) reached. Stop and report results."
          return 1
        fi
      fi
    fi
  fi

  # === PER-TASK LIMIT CHECKS ===
  # Per-task scope is opt-in: requires LANEKEEP_TASK_ID set. Resets on TASK_ID
  # change; does not emit halt signal (per-invocation, not lifetime).
  if [ -n "${LANEKEEP_TASK_ID:-}" ]; then
    local _check_task_actions=$task_action_count
    if [ "$skip_increment" = "true" ]; then
      _check_task_actions=$((_check_task_actions + 1))
    fi

    if [ -n "$max_task_actions" ] && [ "$max_task_actions" != "null" ]; then
      if [ "$_check_task_actions" -gt "$max_task_actions" ]; then
        BUDGET_PASSED=false
        BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nTask action budget exceeded: ${_check_task_actions}/${max_task_actions}"
        BUDGET_HINT="DENIED: Per-task action limit (${max_task_actions}) reached. End this task and report results."
        return 1
      fi
    fi

    if [ -n "$max_task_input_tokens" ] && [ "$max_task_input_tokens" != "null" ]; then
      if [ "$task_input_tokens_st" -gt "$max_task_input_tokens" ]; then
        BUDGET_PASSED=false
        BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nTask input token budget exceeded: ${task_input_tokens_st}/${max_task_input_tokens}"
        BUDGET_HINT="DENIED: Per-task input token limit (${max_task_input_tokens}) reached. End this task and report results."
        return 1
      fi
    fi

    if [ -n "$max_task_output_tokens" ] && [ "$max_task_output_tokens" != "null" ]; then
      if [ "$task_output_tokens_st" -gt "$max_task_output_tokens" ]; then
        BUDGET_PASSED=false
        BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nTask output token budget exceeded: ${task_output_tokens_st}/${max_task_output_tokens}"
        BUDGET_HINT="DENIED: Per-task output token limit (${max_task_output_tokens}) reached. End this task and report results."
        return 1
      fi
    fi

    if [ -n "$max_task_tokens" ] && [ "$max_task_tokens" != "null" ]; then
      if [ "$task_token_count" -gt "$max_task_tokens" ]; then
        BUDGET_PASSED=false
        BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nTask token budget exceeded: ${task_token_count}/${max_task_tokens}"
        BUDGET_HINT="DENIED: Per-task token limit (${max_task_tokens}) reached. End this task and report results."
        return 1
      fi
    fi

    if [ -n "$max_task_time" ] && [ "$max_task_time" != "null" ]; then
      local _task_elapsed=$((now_epoch - ${task_start_epoch%.*}))
      if [ "$_task_elapsed" -gt "$max_task_time" ]; then
        BUDGET_PASSED=false
        BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nTask time budget exceeded: ${_task_elapsed}s/${max_task_time}s"
        local _tkmins=$(( max_task_time / 60 ))
        [ "$_tkmins" -lt 1 ] && _tkmins=1
        BUDGET_HINT="DENIED: Per-task time limit (${_tkmins}min) reached. End this task and report results."
        return 1
      fi
    fi

    if [ -n "$max_task_cost" ] && [ "$max_task_cost" != "null" ]; then
      local _task_cost=""
      local _tcost_model="${_TRANSCRIPT_MODEL:-${_prev_model:-}}"
      local _tpricing_file="${LANEKEEP_DIR:-}/data/pricing.json"
      if [ -n "$_tcost_model" ] && [ -f "$_tpricing_file" ]; then
        local _tcost_ovr='{}'
        if [ -f "$LANEKEEP_CONFIG_FILE" ]; then
          _tcost_ovr=$(jq -c '.budget.pricing_overrides // {}' "$LANEKEEP_CONFIG_FILE" 2>/dev/null) || _tcost_ovr='{}'
        fi
        _task_cost=$(jq -r --arg model "$_tcost_model" \
          --argjson itoks "$task_input_tokens_st" \
          --argjson cctoks "$cache_creation_st" \
          --argjson crtoks "$cache_read_st" \
          --argjson otoks "$task_output_tokens_st" \
          --argjson overrides "$_tcost_ovr" '
          ((.models[$model] // .models[($model | gsub("-[0-9]{8}$";""))]) // {}) as $base |
          (($overrides[$model] // $overrides[($model | gsub("-[0-9]{8}$";""))]) // {}) as $ovr |
          ($base + $ovr) as $p |
          if ($p | has("input_per_mtok")) then
            ((([0, ($itoks - $cctoks - $crtoks)] | max) * $p.input_per_mtok
              + $cctoks * $p.cache_write_per_mtok
              + $crtoks * $p.cache_read_per_mtok
              + $otoks * $p.output_per_mtok) / 1000000) |
            . * 1000000 | round / 1000000
          else 0 end
        ' "$_tpricing_file" 2>/dev/null) || _task_cost=""
      fi
      if [ -n "$_task_cost" ] && [ "$_task_cost" != "0" ]; then
        if jq -e --argjson cost "$_task_cost" --argjson max "$max_task_cost" \
          'if $cost > $max then true else false end' <<< 'null' >/dev/null 2>&1; then
          local _tdisplay_cost
          _tdisplay_cost=$(jq -n --argjson v "$_task_cost" '$v * 100 | round / 100')
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nTask cost budget exceeded: \$${_tdisplay_cost}/\$${max_task_cost}"
          BUDGET_HINT="DENIED: Per-task cost limit (\$${max_task_cost}) reached. End this task and report results."
          return 1
        fi
      fi
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
     || { [ -n "$max_total_time" ] && [ "$max_total_time" != "null" ]; } \
     || { [ -n "$max_total_cost" ] && [ "$max_total_cost" != "null" ]; }; then

    local cumfile="${LANEKEEP_CUMULATIVE_FILE:-${PROJECT_DIR:-.}/.lanekeep/cumulative.json}"
    # AG-001: enforce caps from the very first action, not just after the first
    # session boundary. cumulative_init creates an empty file when none exists.
    if [ ! -f "$cumfile" ] && declare -f cumulative_init >/dev/null 2>&1; then
      LANEKEEP_STATE_FILE="" cumulative_init >/dev/null 2>&1 || true
    fi
    if [ -f "$cumfile" ]; then
      local cum_actions=0 cum_input_tokens=0 cum_output_tokens=0 cum_tokens=0 cum_time=0 cum_cost=0
      eval "$(jq -r '
        "cum_actions=" + (.total_actions // 0 | tostring | @sh),
        "cum_input_tokens=" + (.total_input_tokens // 0 | tostring | @sh),
        "cum_output_tokens=" + (.total_output_tokens // 0 | tostring | @sh),
        "cum_tokens=" + (.total_tokens // 0 | tostring | @sh),
        "cum_time=" + (.total_time_seconds // 0 | tostring | @sh),
        "cum_cost=" + (.total_cost // 0 | tostring | @sh)
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
          BUDGET_HINT="DENIED: All-time action limit (${max_total_actions}) reached. Stop and report results."
          BUDGET_CUMULATIVE_HALTED="true"
          _budget_emit_halt "$BUDGET_REASON"
          return 1
        fi
      fi

      # Check all-time input token limit
      if [ -n "$max_total_input_tokens" ] && [ "$max_total_input_tokens" != "null" ]; then
        if [ "$total_input_toks" -gt "$max_total_input_tokens" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time input token budget exceeded: ${total_input_toks}/${max_total_input_tokens}"
          BUDGET_HINT="DENIED: All-time input token limit (${max_total_input_tokens}) reached. Stop and report results."
          BUDGET_CUMULATIVE_HALTED="true"
          _budget_emit_halt "$BUDGET_REASON"
          return 1
        fi
      fi

      # Check all-time output token limit
      if [ -n "$max_total_output_tokens" ] && [ "$max_total_output_tokens" != "null" ]; then
        if [ "$total_output_toks" -gt "$max_total_output_tokens" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time output token budget exceeded: ${total_output_toks}/${max_total_output_tokens}"
          BUDGET_HINT="DENIED: All-time output token limit (${max_total_output_tokens}) reached. Stop and report results."
          BUDGET_CUMULATIVE_HALTED="true"
          _budget_emit_halt "$BUDGET_REASON"
          return 1
        fi
      fi

      # Check all-time token limit
      if [ -n "$max_total_tokens" ] && [ "$max_total_tokens" != "null" ]; then
        if [ "$total_tokens" -gt "$max_total_tokens" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time token budget exceeded: ${total_tokens}/${max_total_tokens}"
          BUDGET_HINT="DENIED: All-time token limit (${max_total_tokens}) reached. Stop and report results."
          BUDGET_CUMULATIVE_HALTED="true"
          _budget_emit_halt "$BUDGET_REASON"
          return 1
        fi
      fi

      # Check all-time time limit
      if [ -n "$max_total_time" ] && [ "$max_total_time" != "null" ]; then
        if [ "$total_time" -gt "$max_total_time" ]; then
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time time budget exceeded: ${total_time}s/${max_total_time}s"
          local _ttmins=$(( max_total_time / 60 ))
          [ "$_ttmins" -lt 1 ] && _ttmins=1
          BUDGET_HINT="DENIED: All-time time limit (${_ttmins}min) reached. Stop and report results."
          BUDGET_CUMULATIVE_HALTED="true"
          _budget_emit_halt "$BUDGET_REASON"
          return 1
        fi
      fi

      # Check all-time cost limit
      if [ -n "$max_total_cost" ] && [ "$max_total_cost" != "null" ] && [ -n "$_session_cost" ]; then
        if jq -e --argjson cum "$cum_cost" --argjson sess "$_session_cost" --argjson max "$max_total_cost" \
          'if ($cum + $sess) > $max then true else false end' <<< 'null' >/dev/null 2>&1; then
          local _total_cost
          _total_cost=$(jq -n --argjson a "$cum_cost" --argjson b "$_session_cost" '$a + $b | . * 100 | round / 100')
          BUDGET_PASSED=false
          BUDGET_REASON="[LaneKeep] DENIED by BudgetEvaluator (Tier 5, score: 1.0)\nAll-time cost budget exceeded: \$${_total_cost}/\$${max_total_cost}"
          BUDGET_HINT="DENIED: All-time cost limit (\$${max_total_cost}) reached. Stop and report results."
          BUDGET_CUMULATIVE_HALTED="true"
          _budget_emit_halt "$BUDGET_REASON"
          return 1
        fi
      fi
    fi
  fi

  return 0
}
