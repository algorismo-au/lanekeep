#!/usr/bin/env bash
# Cumulative stats tracking across sessions

# Initialize empty cumulative file
_cumulative_empty() {
  printf '{"version":1,"updated_at":"","total_sessions":0,"total_events":0,"total_actions":0,"total_tokens":0,"total_input_tokens":0,"total_output_tokens":0,"total_cache_creation_input_tokens":0,"total_cache_read_input_tokens":0,"total_time_seconds":0,"total_cost":0,"total_cache_savings":0}\n'
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
  local prev_cache_creation=0 prev_cache_read=0 prev_model=""
  eval "$(jq -r '
    "prev_actions=" + (.action_count // 0 | tostring | @sh),
    "prev_events=" + (.total_events // 0 | tostring | @sh),
    "prev_tokens=" + (.token_count // 0 | tostring | @sh),
    "prev_input_tokens=" + (.input_tokens // 0 | tostring | @sh),
    "prev_output_tokens=" + (.output_tokens // 0 | tostring | @sh),
    "prev_cache_creation=" + (.cache_creation_input_tokens // 0 | tostring | @sh),
    "prev_cache_read=" + (.cache_read_input_tokens // 0 | tostring | @sh),
    "prev_start=" + (.start_epoch // 0 | tostring | @sh),
    "prev_model=" + (.model // "" | @sh)
  ' "$state" 2>/dev/null)" || true
  [[ "$prev_actions" =~ ^[0-9]+$ ]] || prev_actions=0
  [[ "$prev_events" =~ ^[0-9]+$ ]] || prev_events=0
  [[ "$prev_tokens" =~ ^[0-9]+$ ]] || prev_tokens=0
  [[ "$prev_input_tokens" =~ ^[0-9]+$ ]] || prev_input_tokens=0
  [[ "$prev_output_tokens" =~ ^[0-9]+$ ]] || prev_output_tokens=0
  [[ "$prev_cache_creation" =~ ^[0-9]+$ ]] || prev_cache_creation=0
  [[ "$prev_cache_read" =~ ^[0-9]+$ ]] || prev_cache_read=0
  [[ "$prev_start" =~ ^[0-9]+$ ]] || prev_start=0

  # Compute session cost from pricing table (with config overrides)
  local session_cost=0 session_savings=0
  local pricing_file="${LANEKEEP_DIR:-}/data/pricing.json"
  local config_file="${LANEKEEP_CONFIG_FILE:-}"
  if [ -n "$prev_model" ] && [ -f "$pricing_file" ]; then
    # Read pricing overrides from config if available
    local _ovr='{}'
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
      _ovr=$(jq -c '.budget.pricing_overrides // {}' "$config_file" 2>/dev/null) || _ovr='{}'
    fi
    eval "$(jq -r --arg model "$prev_model" \
      --argjson itoks "$prev_input_tokens" \
      --argjson cctoks "$prev_cache_creation" \
      --argjson crtoks "$prev_cache_read" \
      --argjson otoks "$prev_output_tokens" \
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
    ' "$pricing_file" 2>/dev/null)" || true
  fi

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
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
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
    if $model != "" then .last_model = $model else . end
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
