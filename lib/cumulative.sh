#!/usr/bin/env bash
# Cumulative stats tracking across sessions

# Initialize empty cumulative file
_cumulative_empty() {
  printf '{"version":1,"updated_at":"","total_sessions":0,"total_events":0,"total_actions":0,"total_tokens":0,"total_input_tokens":0,"total_output_tokens":0,"total_cache_creation_input_tokens":0,"total_cache_read_input_tokens":0,"total_time_seconds":0,"total_cost":0,"total_cache_savings":0}\n'
}

# Compute session cost from token counts + pricing table (with config overrides).
# Args: model itoks cctoks crtoks otoks pricing_file config_file
# Echoes two shell-eval lines:
#   session_cost=<float>
#   session_savings=<float>
# Always exits 0; on missing pricing prints both as 0.
# Shared by cumulative_init (session finalization) and lib/cost-line.sh
# (PR-body / JSON cost exporter) so pricing math has a single source of truth.
cumulative::_calc_cost_jq() {
  local model="$1" itoks="$2" cctoks="$3" crtoks="$4" otoks="$5"
  local pricing_file="$6" config_file="$7"

  if [ -z "$model" ] || [ ! -f "$pricing_file" ]; then
    printf 'session_cost=0\nsession_savings=0\n'
    return 0
  fi

  local _ovr='{}'
  if [ -n "$config_file" ] && [ -f "$config_file" ]; then
    _ovr=$(jq -c '.budget.pricing_overrides // {}' "$config_file" 2>/dev/null) || _ovr='{}'
  fi

  jq -r --arg model "$model" \
    --argjson itoks "$itoks" \
    --argjson cctoks "$cctoks" \
    --argjson crtoks "$crtoks" \
    --argjson otoks "$otoks" \
    --argjson overrides "$_ovr" '
    ((.models[$model] // .models[($model | gsub("-[0-9]{8}$";""))]) // {}) as $base |
    (($overrides[$model] // $overrides[($model | gsub("-[0-9]{8}$";""))]) // {}) as $ovr |
    ($base + $ovr) as $p |
    if ($p | has("input_per_mtok")) then
      ((([0, ($itoks - $cctoks - $crtoks)] | max) * $p.input_per_mtok
        + $cctoks * $p.cache_write_per_mtok
        + $crtoks * $p.cache_read_per_mtok
        + $otoks * $p.output_per_mtok) / 1000000) as $cost_raw |
      (($crtoks * ($p.input_per_mtok - $p.cache_read_per_mtok)) / 1000000) as $sav_raw |
      "session_cost=\($cost_raw * 1000000 | round / 1000000)",
      "session_savings=\($sav_raw * 1000000 | round / 1000000)"
    else
      "session_cost=0", "session_savings=0"
    end
  ' "$pricing_file" 2>/dev/null || printf 'session_cost=0\nsession_savings=0\n'
}

# Persist a per-session summary file so cross-session aggregators can read
# completed session data without depending on the rolling cumulative.json.
# Args: sessions_dir session_id task_id model itoks otoks cctoks crtoks
#       start_epoch elapsed cost savings
# Best-effort: never fails the caller.
cumulative::_write_session_summary() {
  local sessions_dir="$1" sid="$2" tid="$3" model="$4"
  local itoks="$5" otoks="$6" cctoks="$7" crtoks="$8"
  local start_epoch="$9" elapsed="${10}" cost="${11}" savings="${12}"

  [ -z "$sid" ] && return 0
  (umask 077; mkdir -p "$sessions_dir") || return 0

  local end_epoch=$((start_epoch + elapsed))
  local out="$sessions_dir/${sid}.summary.json"

  jq -n \
    --arg sid "$sid" --arg tid "$tid" --arg model "$model" \
    --argjson itoks "$itoks" --argjson otoks "$otoks" \
    --argjson cctoks "$cctoks" --argjson crtoks "$crtoks" \
    --argjson start "$start_epoch" --argjson end_e "$end_epoch" \
    --argjson dur "$elapsed" \
    --argjson cost "$cost" --argjson savings "$savings" '
    {
      version: 1,
      session_id: $sid,
      task_id: $tid,
      model: $model,
      input_tokens: $itoks,
      output_tokens: $otoks,
      cache_creation_input_tokens: $cctoks,
      cache_read_input_tokens: $crtoks,
      start_epoch: $start,
      end_epoch: $end_e,
      duration_seconds: $dur,
      cost: $cost,
      cache_savings: $savings
    }
    | if $tid == "" then del(.task_id) else . end
    | if $model == "" then del(.model) else . end
  ' > "${out}.tmp" 2>/dev/null && mv "${out}.tmp" "$out"
  return 0
}

# Called at session start, before state.json resets.
# Finalizes previous session's counters into cumulative.json.
cumulative_init() {
  local cumfile="${LANEKEEP_CUMULATIVE_FILE:-${PROJECT_DIR:-.}/.lanekeep/cumulative.json}"
  local state="${LANEKEEP_STATE_FILE:-}"
  local lockfile="${cumfile}.lock"

  (umask 077; mkdir -p "$(dirname "$cumfile")")

  # If no prior state.json, just ensure cumulative exists
  if [ -z "$state" ] || [ ! -f "$state" ]; then
    if [ ! -f "$cumfile" ]; then
      _cumulative_empty > "$cumfile"
    fi
    return 0
  fi

  # Read previous session's final counters
  local prev_actions=0 prev_events=0 prev_tokens=0 prev_input_tokens=0 prev_output_tokens=0 prev_start=0
  local prev_cache_creation=0 prev_cache_read=0 prev_model="" prev_session_id="" prev_task_id=""
  eval "$(jq -r '
    "prev_actions=" + (.action_count // 0 | tostring | @sh),
    "prev_events=" + (.total_events // 0 | tostring | @sh),
    "prev_tokens=" + (.token_count // 0 | tostring | @sh),
    "prev_input_tokens=" + (.input_tokens // 0 | tostring | @sh),
    "prev_output_tokens=" + (.output_tokens // 0 | tostring | @sh),
    "prev_cache_creation=" + (.cache_creation_input_tokens // 0 | tostring | @sh),
    "prev_cache_read=" + (.cache_read_input_tokens // 0 | tostring | @sh),
    "prev_start=" + (.start_epoch // 0 | tostring | @sh),
    "prev_model=" + (.model // "" | @sh),
    "prev_session_id=" + (.session_id // "" | @sh),
    "prev_task_id=" + (.task_id // "" | @sh)
  ' "$state" 2>/dev/null)" || true
  [[ "$prev_actions" =~ ^[0-9]+$ ]] || prev_actions=0
  [[ "$prev_events" =~ ^[0-9]+$ ]] || prev_events=0
  [[ "$prev_tokens" =~ ^[0-9]+$ ]] || prev_tokens=0
  [[ "$prev_input_tokens" =~ ^[0-9]+$ ]] || prev_input_tokens=0
  [[ "$prev_output_tokens" =~ ^[0-9]+$ ]] || prev_output_tokens=0
  [[ "$prev_cache_creation" =~ ^[0-9]+$ ]] || prev_cache_creation=0
  [[ "$prev_cache_read" =~ ^[0-9]+$ ]] || prev_cache_read=0
  [[ "$prev_start" =~ ^[0-9]+$ ]] || prev_start=0

  # AG-006: read per_agent block from the finalizing session (may be empty {}).
  local prev_per_agent
  prev_per_agent=$(jq -c '.per_agent // {}' "$state" 2>/dev/null) || prev_per_agent='{}'

  # Compute session cost from pricing table (with config overrides)
  local session_cost=0 session_savings=0
  local pricing_file="${LANEKEEP_DIR:-}/data/pricing.json"
  local config_file="${LANEKEEP_CONFIG_FILE:-}"
  eval "$(cumulative::_calc_cost_jq \
    "$prev_model" "$prev_input_tokens" "$prev_cache_creation" \
    "$prev_cache_read" "$prev_output_tokens" \
    "$pricing_file" "$config_file")" || true

  # Compute elapsed time
  local now elapsed=0
  now=$(date +%s)
  if [ "$prev_start" -gt 0 ]; then
    elapsed=$((now - prev_start))
    [ "$elapsed" -lt 0 ] && elapsed=0
  fi

  # Skip finalization if previous session had no activity
  if [ "$prev_actions" -eq 0 ] && [ "$prev_tokens" -eq 0 ]; then
    if [ ! -f "$cumfile" ]; then
      _cumulative_empty > "$cumfile"
    fi
    return 0
  fi

  # Persist per-session summary so task-scoped aggregators can read
  # completed-session data independently of the cumulative roll-up.
  local sessions_dir="${LANEKEEP_SESSIONS_DIR:-${PROJECT_DIR:-.}/.lanekeep/sessions}"
  cumulative::_write_session_summary \
    "$sessions_dir" "$prev_session_id" "$prev_task_id" "$prev_model" \
    "$prev_input_tokens" "$prev_output_tokens" \
    "$prev_cache_creation" "$prev_cache_read" \
    "$prev_start" "$elapsed" "$session_cost" "$session_savings"

  # Lock and update
  exec 8>"$lockfile"
  if ! flock -w 2 8; then
    exec 8>&-
    return 0
  fi

  if [ ! -f "$cumfile" ]; then
    _cumulative_empty > "$cumfile"
  fi

  local updated
  updated=$(jq \
    --argjson acts "$prev_actions" \
    --argjson evts "$prev_events" \
    --argjson toks "$prev_tokens" \
    --argjson itoks "$prev_input_tokens" \
    --argjson otoks "$prev_output_tokens" \
    --argjson cctoks "$prev_cache_creation" \
    --argjson crtoks "$prev_cache_read" \
    --argjson secs "$elapsed" \
    --argjson cost "$session_cost" \
    --argjson savings "$session_savings" \
    --arg model "$prev_model" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson pa "$prev_per_agent" '
    .updated_at = $now |
    .total_sessions += 1 |
    .total_events += $evts |
    .total_actions += $acts |
    .total_tokens += $toks |
    .total_input_tokens = ((.total_input_tokens // 0) + $itoks) |
    .total_output_tokens = ((.total_output_tokens // 0) + $otoks) |
    .total_cache_creation_input_tokens = ((.total_cache_creation_input_tokens // 0) + $cctoks) |
    .total_cache_read_input_tokens = ((.total_cache_read_input_tokens // 0) + $crtoks) |
    .total_time_seconds += $secs |
    .total_cost = ((.total_cost // 0) + $cost) |
    .total_cache_savings = ((.total_cache_savings // 0) + $savings) |
    if $model != "" then .last_model = $model else . end |
    # AG-006: fold per-agent buckets from the closing session into per-agent
    # cumulative counters. Only agents that had activity this session get a
    # total_sessions bump; the global total_sessions counter is untouched.
    # TODO(AG-006-cost): compute per-agent cost via cumulative::_calc_cost_jq
    # once we track per-agent token totals against pricing. For now, per-agent
    # total_cost and total_cache_savings stay 0.
    reduce ($pa | to_entries[]) as $e (.;
      .per_agent[$e.key] = (
        (.per_agent[$e.key] // {
          total_sessions: 0,
          total_actions: 0,
          total_input_tokens: 0,
          total_output_tokens: 0,
          total_tokens: 0,
          total_cache_creation_input_tokens: 0,
          total_cache_read_input_tokens: 0,
          total_time_seconds: 0,
          total_cost: 0,
          total_cache_savings: 0,
          last_seen_at: ""
        }) as $b |
        $b
        | .total_sessions = ($b.total_sessions + 1)
        | .total_actions = ($b.total_actions + ($e.value.action_count // 0))
        | .total_input_tokens = ($b.total_input_tokens + ($e.value.input_tokens // 0))
        | .total_output_tokens = ($b.total_output_tokens + ($e.value.output_tokens // 0))
        | .total_tokens = ($b.total_tokens + ($e.value.token_count // 0))
        | .total_cache_creation_input_tokens = ($b.total_cache_creation_input_tokens + ($e.value.cache_creation_input_tokens // 0))
        | .total_cache_read_input_tokens = ($b.total_cache_read_input_tokens + ($e.value.cache_read_input_tokens // 0))
        | .total_time_seconds = ($b.total_time_seconds + $secs)
        | .last_seen_at = $now
      )
    )
  ' "$cumfile" 2>/dev/null) || { exec 8>&-; return 0; }

  printf '%s\n' "$updated" > "${cumfile}.tmp" && mv "${cumfile}.tmp" "$cumfile"
  exec 8>&-
  return 0
}

# Called per-action from lanekeep-handler.
# Args: decision tool_name pii_in(0/1) failed_evals(comma-sep) [now_iso] [latency_ms]
cumulative_record() {
  local decision="${1:-}"
  local tool_name="${2:-}"
  local pii_in="${3:-0}"
  local failed_evals="${4:-}"
  local now_iso="${5:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local latency_ms="${6:-}"

  local cumfile="${LANEKEEP_CUMULATIVE_FILE:-${PROJECT_DIR:-.}/.lanekeep/cumulative.json}"
  local lockfile="${cumfile}.lock"

  if [ ! -f "$cumfile" ]; then
    (umask 077; mkdir -p "$(dirname "$cumfile")")
    _cumulative_empty > "$cumfile"
  fi

  exec 8>"$lockfile"
  if ! flock -n 8; then
    exec 8>&-
    return 0
  fi

  local updated
  updated=$(jq \
    --arg dec "$decision" \
    --arg tool "$tool_name" \
    --argjson pii_in "$pii_in" \
    --arg evals "$failed_evals" \
    --arg now "$now_iso" \
    --arg lat "$latency_ms" '
    .updated_at = $now |
    if $dec != "" then
      .decisions[$dec] = ((.decisions[$dec] // 0) + 1)
    else . end |
    if $dec == "deny" and $tool != "" then
      .top_denied_tools[$tool] = ((.top_denied_tools[$tool] // 0) + 1)
    else . end |
    if $pii_in > 0 then .pii.input += $pii_in else . end |
    if $evals != "" then
      reduce ($evals | split(",") | .[]) as $ev (.;
        if $ev != "" then
          .top_evaluators[$ev] = ((.top_evaluators[$ev] // 0) + 1)
        else . end
      )
    else . end |
    if $lat != "" then
      ($lat | tonumber) as $lms |
      .latency = ((.latency // {count:0,sum_ms:0,max_ms:0,values:[]}) |
        .count += 1 |
        .sum_ms += $lms |
        .max_ms = ([.max_ms, $lms] | max) |
        .values = ((.values // []) + [$lms]))
    else . end
  ' "$cumfile" 2>/dev/null) || { exec 8>&-; return 0; }

  printf '%s\n' "$updated" > "${cumfile}.tmp" && mv "${cumfile}.tmp" "$cumfile"
  exec 8>&-
  return 0
}
