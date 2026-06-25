#!/usr/bin/env bash
# Cost-line exporter — formats per-session cost/attempts/duration/models for
# PR bodies and structured tooling. See specs/COST-LINE-EXPORTER.md.
#
# Public API:
#   cost_line::emit_cost_line <scope> <id> <with_savings>   # one-line text
#   cost_line::emit_json      <scope> <id>                  # JSON object
#
# Both write to stdout on success (exit 0) or write a stderr message and
# exit 1 on no-data. <scope> is "session" or "task"; empty <id> = current.

# Source pricing helper (single source of truth across cumulative + cost-line)
# shellcheck source=/dev/null
. "${LANEKEEP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/cumulative.sh"

# --- Pure formatters (no I/O) -----------------------------------------------

# Strip "claude-" prefix, strip trailing date (-YYYYMMDD or -YYYY-MM-DD),
# convert trailing -N-N to .N.N
cost_line::_normalize_model() {
  local raw="$1" m
  m="${raw#claude-}"
  m=$(printf '%s' "$m" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}$//; s/-[0-9]{8}$//')
  m=$(printf '%s' "$m" | sed -E 's/^(.+)-([0-9]+)-([0-9]+)$/\1-\2.\3/')
  printf '%s' "$m"
}

# $%.2f, or $%.4f if 0 < c < $0.01. Exact zero uses $0.00.
cost_line::_fmt_cost() {
  awk -v c="$1" 'BEGIN {
    if (c+0 == 0)         { printf "$0.00" }
    else if (c+0 < 0.01)  { printf "$%.4f", c+0 }
    else                  { printf "$%.2f", c+0 }
  }'
}

# Xs / Xm / XhYm
cost_line::_fmt_duration() {
  local s="$1"
  if [ "$s" -lt 60 ]; then
    printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then
    printf '%dm' $((s / 60))
  else
    printf '%dh%dm' $((s / 3600)) $(( (s % 3600) / 60 ))
  fi
}

# Reads raw model names from stdin (one per line). Emits normalized + deduped,
# chronological order preserved.
cost_line::_dedup_models() {
  local raw
  while IFS= read -r raw; do
    [ -z "$raw" ] && continue
    cost_line::_normalize_model "$raw"
    printf '\n'
  done | awk 'NF && !seen[$0]++'
}

# Reads normalized model names from stdin. Emits joined-with-+ string capped
# at 3, with "+Nmore" suffix if more than 3.
cost_line::_join_models_capped() {
  awk '
    { lines[++n] = $0 }
    END {
      if (n == 0) exit 0
      cap = (n > 3 ? 3 : n)
      for (i = 1; i <= cap; i++) printf "%s%s", (i > 1 ? "+" : ""), lines[i]
      if (n > 3) printf "+%dmore", n - 3
    }
  '
}

# --- Data layer (v1: current session only) ----------------------------------

# Reads state.json into shell vars: model itoks otoks cctoks crtoks
# start_epoch session_id task_id. Returns 1 if state file missing.
cost_line::_read_state() {
  local state_file="$1"
  [ -f "$state_file" ] || return 1
  jq -r '
    "model=" + (.model // "" | @sh),
    "itoks=" + (.input_tokens // 0 | tostring | @sh),
    "otoks=" + (.output_tokens // 0 | tostring | @sh),
    "cctoks=" + (.cache_creation_input_tokens // 0 | tostring | @sh),
    "crtoks=" + (.cache_read_input_tokens // 0 | tostring | @sh),
    "start_epoch=" + (.start_epoch // 0 | tostring | @sh),
    "session_id=" + (.session_id // "" | @sh),
    "task_id=" + (.task_id // "" | @sh)
  ' "$state_file" 2>/dev/null
}

# Float addition helper (awk for portability across bash / no bc dependency)
cost_line::_addf() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.6f", a+b }'
}

# Compute live cost/duration for the current session from state.json. Sets:
#   CUR_HAS=true|false  CUR_MODEL  CUR_SESSION_ID  CUR_TASK_ID
#   CUR_COST  CUR_SAVINGS  CUR_DURATION
cost_line::_load_current() {
  local state_file="$1"
  local pricing_file="$2" config_file="$3"

  CUR_HAS=false
  CUR_MODEL="" CUR_SESSION_ID="" CUR_TASK_ID=""
  CUR_COST=0 CUR_SAVINGS=0 CUR_DURATION=0

  local _s
  _s=$(cost_line::_read_state "$state_file") || return 0
  local model="" itoks=0 otoks=0 cctoks=0 crtoks=0 start_epoch=0 session_id="" task_id=""
  eval "$_s" || return 0
  [[ "$itoks" =~ ^[0-9]+$ ]] || itoks=0
  [[ "$otoks" =~ ^[0-9]+$ ]] || otoks=0
  [[ "$cctoks" =~ ^[0-9]+$ ]] || cctoks=0
  [[ "$crtoks" =~ ^[0-9]+$ ]] || crtoks=0
  [[ "$start_epoch" =~ ^[0-9]+$ ]] || start_epoch=0

  CUR_MODEL="$model"
  CUR_SESSION_ID="$session_id"
  CUR_TASK_ID="$task_id"

  if [ -z "$model" ] && [ "$itoks" -eq 0 ] && [ "$otoks" -eq 0 ]; then
    return 0
  fi
  CUR_HAS=true

  local session_cost=0 session_savings=0
  eval "$(cumulative::_calc_cost_jq \
    "$model" "$itoks" "$cctoks" "$crtoks" "$otoks" \
    "$pricing_file" "$config_file")" || true
  CUR_COST="$session_cost"
  CUR_SAVINGS="$session_savings"

  local now
  now=$(date +%s)
  if [ "$start_epoch" -gt 0 ]; then
    CUR_DURATION=$((now - start_epoch))
    [ "$CUR_DURATION" -lt 0 ] && CUR_DURATION=0
  fi
}

# Read a single .summary.json file's fields into the aggregation accumulators.
# Args: file (full path)
# Reads global: TARGET_TASK_ID (when set, only include if .task_id matches)
# Mutates accumulators: AGG_COST AGG_SAVINGS AGG_DURATION AGG_ATTEMPTS
# Appends model to: AGG_MODELS_FILE (when non-empty)
# Returns 0 if included, 1 if filtered out or unreadable.
cost_line::_ingest_summary() {
  local f="$1"
  local sum_cost=0 sum_savings=0 sum_dur=0 sum_model="" sum_task=""
  eval "$(jq -r '
    "sum_cost=" + (.cost // 0 | tostring | @sh),
    "sum_savings=" + (.cache_savings // 0 | tostring | @sh),
    "sum_dur=" + (.duration_seconds // 0 | tostring | @sh),
    "sum_model=" + (.model // "" | @sh),
    "sum_task=" + (.task_id // "" | @sh)
  ' "$f" 2>/dev/null)" || return 1

  if [ -n "${TARGET_TASK_ID:-}" ] && [ "$sum_task" != "$TARGET_TASK_ID" ]; then
    return 1
  fi

  AGG_COST=$(cost_line::_addf "$AGG_COST" "$sum_cost")
  AGG_SAVINGS=$(cost_line::_addf "$AGG_SAVINGS" "$sum_savings")
  AGG_DURATION=$((AGG_DURATION + sum_dur))
  AGG_ATTEMPTS=$((AGG_ATTEMPTS + 1))
  [ -n "$sum_model" ] && printf '%s\n' "$sum_model" >> "$AGG_MODELS_FILE"
  return 0
}

# Compute scope; populates CL_* globals on success. Returns 1 on no-data.
cost_line::_compute() {
  local scope="$1" id="$2"
  local state_file="${LANEKEEP_STATE_FILE:-${PROJECT_DIR:-.}/.lanekeep/state.json}"
  local sessions_dir="${LANEKEEP_SESSIONS_DIR:-${PROJECT_DIR:-.}/.lanekeep/sessions}"
  local pricing_file="${LANEKEEP_DIR:-}/data/pricing.json"
  local config_file="${LANEKEEP_CONFIG_FILE:-}"

  # Load current session data (may have no activity)
  cost_line::_load_current "$state_file" "$pricing_file" "$config_file"

  # Initialize accumulators
  AGG_COST=0 AGG_SAVINGS=0 AGG_DURATION=0 AGG_ATTEMPTS=0
  AGG_MODELS_FILE=$(mktemp)
  TARGET_TASK_ID=""

  # Resolve scope and figure out what to include
  local resolved_id="$id" include_current=false
  case "$scope" in
    session)
      if [ -z "$id" ] || [ "$id" = "$CUR_SESSION_ID" ]; then
        # Current session
        if [ "$CUR_HAS" = "true" ]; then
          include_current=true
          resolved_id="$CUR_SESSION_ID"
        fi
      else
        # Specific archived session
        local f="$sessions_dir/${id}.summary.json"
        if [ -f "$f" ]; then
          cost_line::_ingest_summary "$f" || true
        fi
      fi
      ;;
    task)
      # Resolve target task id
      local target="$id"
      [ -z "$target" ] && target="$CUR_TASK_ID"
      if [ -z "$target" ]; then
        rm -f "$AGG_MODELS_FILE"
        return 1
      fi
      resolved_id="$target"
      TARGET_TASK_ID="$target"

      # Include current session when its task matches
      if [ "$CUR_HAS" = "true" ] && [ "$CUR_TASK_ID" = "$target" ]; then
        include_current=true
      fi

      # Scan archived summaries (chronological by session-id timestamp prefix)
      if [ -d "$sessions_dir" ]; then
        local f
        while IFS= read -r -d '' f; do
          # Don't double-count the current session if it also has a summary
          local sum_sid
          sum_sid=$(jq -r '.session_id // ""' "$f" 2>/dev/null) || sum_sid=""
          [ "$sum_sid" = "$CUR_SESSION_ID" ] && continue
          cost_line::_ingest_summary "$f" || true
        done < <(find "$sessions_dir" -maxdepth 1 -name '*.summary.json' -print0 2>/dev/null | sort -z)
      fi
      ;;
  esac

  # Add current session if in scope (after archived, so it appears chronologically last)
  if [ "$include_current" = "true" ]; then
    AGG_COST=$(cost_line::_addf "$AGG_COST" "$CUR_COST")
    AGG_SAVINGS=$(cost_line::_addf "$AGG_SAVINGS" "$CUR_SAVINGS")
    AGG_DURATION=$((AGG_DURATION + CUR_DURATION))
    AGG_ATTEMPTS=$((AGG_ATTEMPTS + 1))
    [ -n "$CUR_MODEL" ] && printf '%s\n' "$CUR_MODEL" >> "$AGG_MODELS_FILE"
  fi

  if [ "$AGG_ATTEMPTS" -eq 0 ]; then
    rm -f "$AGG_MODELS_FILE"
    return 1
  fi

  local models_normalized
  models_normalized=$(cost_line::_dedup_models < "$AGG_MODELS_FILE")
  rm -f "$AGG_MODELS_FILE"

  CL_COST="$AGG_COST"
  CL_SAVINGS="$AGG_SAVINGS"
  CL_ATTEMPTS="$AGG_ATTEMPTS"
  CL_DURATION="$AGG_DURATION"
  CL_MODELS_NORMALIZED="$models_normalized"
  CL_SCOPE="$scope"
  CL_SESSION_ID="$CUR_SESSION_ID"
  CL_RESOLVED_ID="$resolved_id"
  return 0
}

# Stderr message for no-data path.
cost_line::_no_data_msg() {
  local scope="$1" id="$2"
  if [ -n "$id" ]; then
    printf 'no data for %s %s\n' "$scope" "$id"
  else
    printf 'no data available\n'
  fi
}

# --- Public emitters --------------------------------------------------------

# Args: scope ("session"|"task"), id (may be empty), with_savings ("1"|"0")
cost_line::emit_cost_line() {
  local scope="$1" id="$2" with_savings="${3:-0}"

  if ! cost_line::_compute "$scope" "$id"; then
    cost_line::_no_data_msg "$scope" "$id" >&2
    return 1
  fi

  local out
  out=$(cost_line::_fmt_cost "$CL_COST")

  # Savings segment — opt-in, omitted when zero
  if [ "$with_savings" = "1" ] && awk -v s="$CL_SAVINGS" 'BEGIN { exit !(s+0 > 0) }'; then
    out="$out · saved $(cost_line::_fmt_cost "$CL_SAVINGS")"
  fi

  # Attempts (singular form for 1)
  local att_word="attempts"
  [ "$CL_ATTEMPTS" -eq 1 ] && att_word="attempt"
  out="$out · ${CL_ATTEMPTS} ${att_word}"

  # Duration
  out="$out · $(cost_line::_fmt_duration "$CL_DURATION")"

  # Models (segment omitted if empty)
  if [ -n "$CL_MODELS_NORMALIZED" ]; then
    local joined
    joined=$(printf '%s\n' "$CL_MODELS_NORMALIZED" | cost_line::_join_models_capped)
    [ -n "$joined" ] && out="$out · $joined"
  fi

  printf '%s\n' "$out"
}

# Args: scope ("session"|"task"), id (may be empty)
cost_line::emit_json() {
  local scope="$1" id="$2"

  if ! cost_line::_compute "$scope" "$id"; then
    cost_line::_no_data_msg "$scope" "$id" >&2
    return 1
  fi

  local out_id="${CL_RESOLVED_ID:-$CL_SESSION_ID}"

  # Models as JSON array (no cap in JSON output)
  local models_json='[]'
  if [ -n "$CL_MODELS_NORMALIZED" ]; then
    models_json=$(printf '%s\n' "$CL_MODELS_NORMALIZED" | jq -R . | jq -sc 'map(select(length > 0))')
  fi

  # Pass cost/savings as strings then |tonumber inside jq so jq normalizes the
  # float representation (the accumulator's "%.6f" padding becomes canonical).
  jq -nc \
    --arg scope "$CL_SCOPE" \
    --arg id "$out_id" \
    --arg cost "$CL_COST" \
    --arg cache_savings "$CL_SAVINGS" \
    --argjson attempts "$CL_ATTEMPTS" \
    --argjson duration "$CL_DURATION" \
    --argjson models "$models_json" \
    '{scope:$scope, id:$id, cost:(($cost|tonumber)+0), cache_savings:(($cache_savings|tonumber)+0),
      attempts:$attempts, duration_seconds:$duration, models:$models}'
}
