#!/usr/bin/env bash
# Append-only JSONL trace entries and policy lifecycle events

# H4: Redact known secret patterns before trace logging
# Takes a string (typically JSON tool_input) on stdin or as $1,
# returns the redacted version on stdout. Idempotent and sed-only.
_redact_secrets() {
  local input="${1-}"
  # If no arg, read from stdin
  if [ -z "$input" ]; then
    input=$(cat)
  fi
  # Return empty/null as-is
  if [ -z "$input" ] || [ "$input" = "null" ]; then
    printf '%s' "$input"
    return 0
  fi
  printf '%s' "$input" | sed -E \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED:aws-key]/g' \
    -e 's/gh[pousr]_[A-Za-z0-9]{36}/[REDACTED:github-token]/g' \
    -e 's/sk-ant-[A-Za-z0-9_-]{20,}/[REDACTED:api-key]/g' \
    -e 's/sk-[A-Za-z0-9]{20,}/[REDACTED:api-key]/g' \
    -e 's/Bearer [A-Za-z0-9._-]+/Bearer [REDACTED]/g' \
    -e 's/("(api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token|password|credential|secret)"\s*:\s*")[A-Za-z0-9+\/=]{32,}"/\1[REDACTED:secret]"/gI'
}

# VULN-14: Validate trace path is within expected .lanekeep/ directory
_validate_trace_path() {
  local trace_path="$1"
  local resolved
  # Resolve parent dir (file may not exist yet)
  local dir_resolved base_name
  dir_resolved="$(cd "$(dirname "$trace_path")" 2>/dev/null && pwd)" || {
    echo "[LaneKeep] ERROR: Trace directory does not exist: $(dirname "$trace_path")" >&2
    return 1
  }
  base_name="$(basename "$trace_path")"
  resolved="${dir_resolved}/${base_name}"
  # Use realpath for canonical path and compare against known-good suffix
  local canonical
  canonical=$(realpath -m "$resolved" 2>/dev/null) || canonical="$resolved"
  # Verify the canonical path ends with /.lanekeep/traces/<filename>
  case "$canonical" in
    */.lanekeep/traces/"$base_name") return 0 ;;
    *)
      echo "[LaneKeep] ERROR: Trace path '$trace_path' is outside .lanekeep/traces/" >&2
      return 1
      ;;
  esac
}

# VULN-13: Locked append to prevent interleaved writes
_locked_append() {
  local file="$1"
  local data="$2"
  (
    flock -w 10 200 || { echo "[LaneKeep] ERROR: Failed to lock trace file — audit entry dropped" >&2; return 1; }
    printf '%s\n' "$data" >> "$file"
    chmod 600 "$file" 2>/dev/null || true
  ) 200>"${file}.lock"
}

write_trace() {
  # Accept optional ISO timestamp as first arg (1B — avoids date subprocess)
  local _ts_override=""
  if [[ "$1" == 20[0-9][0-9]-* ]]; then
    _ts_override="$1"
    shift
  fi
  local tool_name="$1"
  local tool_input="$2"
  local decision="$3"
  local reason="$4"
  local latency_ms="$5"
  local event_type="$6"
  shift 6

  # Detect tool_use_id (new 7-arg style) vs evaluator result (old 6-arg style)
  # tool_use_id is a simple string (e.g. "toolu_..."), evaluator results start with "{"
  local tool_use_id=""
  if [ $# -gt 0 ] && [ "${1:0:1}" != "{" ]; then
    tool_use_id="$1"
    shift
  fi
  local results=("$@")

  # Default event_type for backward compatibility
  case "$event_type" in
    PreToolUse|PostToolUse|ToolResultTransform) ;;
    *)
      # Not an event type — treat as evaluator result (old call style)
      if [ -n "$tool_use_id" ]; then
        results=("$event_type" "$tool_use_id" "${results[@]}")
      else
        results=("$event_type" "${results[@]}")
      fi
      event_type="PreToolUse"
      tool_use_id=""
      ;;
  esac

  # Inline Ralph context (no subprocess — read state file directly)
  local ralph_ctx='{"iteration":0,"hat":"unknown","topic":"unknown"}'
  local _rs="${LANEKEEP_STATE_DIR:-.lanekeep}/ralph-state.json"
  if [ -f "$_rs" ]; then
    ralph_ctx=$(<"$_rs") 2>/dev/null || ralph_ctx='{"iteration":0,"hat":"unknown","topic":"unknown"}'
    [[ "$ralph_ctx" == "{"* ]] || ralph_ctx='{"iteration":0,"hat":"unknown","topic":"unknown"}'
  fi

  # Ensure trace directory exists with restrictive permissions
  mkdir -p -m 0700 "$(dirname "$LANEKEEP_TRACE_FILE")"

  # Validate and append trace entry
  _validate_trace_path "$LANEKEEP_TRACE_FILE" || return 0

  # H4: Scrub secrets from tool_input before trace logging
  tool_input=$(_redact_secrets "$tool_input")

  # Single jq call: build evals array + extract compliance + build entry (3→1 subprocess)
  local entry
  local _ts="${_ts_override:-$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)}"
  entry=$(printf '%s\n' "${results[@]}" | jq -sc \
    --arg ts "$_ts" \
    --arg sid "${LANEKEEP_SESSION_ID:-unknown}" \
    --arg et "$event_type" \
    --arg tn "$tool_name" \
    --argjson ti "$tool_input" \
    --arg dec "$decision" \
    --arg rea "$reason" \
    --argjson lat "$latency_ms" \
    --argjson ralph "$ralph_ctx" \
    --arg chash "${LANEKEEP_CONFIG_HASH:-unknown}" \
    --arg tuid "$tool_use_id" \
    --arg ud "${_TRACE_USER_DENIED:-false}" \
    '. as $evals |
     ([.[].compliance? // [] | .[]] | unique | if length == 0 then null else . end) as $comp |
     {timestamp:$ts,source:"lanekeep",session_id:$sid,event_type:$et,tool_name:$tn,tool_input:$ti,
       decision:$dec,reason:$rea,latency_ms:$lat,evaluators:$evals,ralph:$ralph,
       config_hash:$chash}
     | if $comp then .compliance = $comp else . end
     | if $tuid != "" then .tool_use_id = $tuid else . end
     | if $ud == "true" then .user_denied = true else . end
     | if ($ti | type == "object") and ($ti.file_path? // "" | length > 0) then .file_path = $ti.file_path else . end')
  _locked_append "$LANEKEEP_TRACE_FILE" "$entry"
}

write_policy_event() {
  local event="$1"
  local policy="$2"
  local type="$3"
  local user="$4"
  local reason="$5"

  mkdir -p -m 0700 "$(dirname "$LANEKEEP_TRACE_FILE")"

  _validate_trace_path "$LANEKEEP_TRACE_FILE" || return 0

  local entry
  entry=$(jq -n -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
    --arg sid "${LANEKEEP_SESSION_ID:-unknown}" \
    --arg ev "$event" \
    --arg pol "$policy" \
    --arg typ "$type" \
    --arg usr "$user" \
    --arg rea "$reason" \
    '{timestamp:$ts,source:"lanekeep",session_id:$sid,event:$ev,policy:$pol,type:$typ,user:$usr,reason:$rea}')
  _locked_append "$LANEKEEP_TRACE_FILE" "$entry"
}

write_rule_event() {
  local event="$1"
  local rule_index="$2"
  local type="$3"
  local user="$4"
  local reason="$5"

  mkdir -p -m 0700 "$(dirname "$LANEKEEP_TRACE_FILE")"
  _validate_trace_path "$LANEKEEP_TRACE_FILE" || return 0

  local entry
  entry=$(jq -n -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
    --arg sid "${LANEKEEP_SESSION_ID:-unknown}" \
    --arg ev "$event" \
    --argjson idx "$rule_index" \
    --arg typ "$type" \
    --arg usr "$user" \
    --arg rea "$reason" \
    '{timestamp:$ts,source:"lanekeep",session_id:$sid,event:$ev,rule_index:$idx,type:$typ,user:$usr,reason:$rea}')
  _locked_append "$LANEKEEP_TRACE_FILE" "$entry"
}

# Prune old trace files by age and/or count
# Args: trace_dir retention_days max_sessions keep_current current_session_id
prune_traces() {
  local trace_dir="$1"
  local retention_days="${2:-0}"
  local max_sessions="${3:-0}"
  local keep_current="${4:-true}"
  local current_session_id="${5:-}"

  # Path traversal protection: must end with /.lanekeep/traces
  local canonical
  canonical=$(realpath -m "$trace_dir" 2>/dev/null) || canonical="$trace_dir"
  case "$canonical" in
    */.lanekeep/traces) ;;
    *)
      echo "[LaneKeep] ERROR: prune_traces refused — path '$trace_dir' is not a .lanekeep/traces directory" >&2
      return 1
      ;;
  esac

  [ -d "$trace_dir" ] || return 0

  PRUNE_DELETED=0
  PRUNE_FREED_BYTES=0

  # Build list of current session file to protect
  local current_file=""
  if [ "$keep_current" = "true" ] && [ -n "$current_session_id" ]; then
    current_file="${trace_dir}/${current_session_id}.jsonl"
  fi

  # Collect candidate files
  local -a candidates=()
  while IFS= read -r -d '' f; do
    # Skip current session file
    if [ -n "$current_file" ] && [ "$(realpath -m "$f" 2>/dev/null)" = "$(realpath -m "$current_file" 2>/dev/null)" ]; then
      continue
    fi
    candidates+=("$f")
  done < <(find "$trace_dir" -maxdepth 1 -name '*.jsonl' -print0 2>/dev/null)

  # Phase 1: age filter — delete files older than retention_days
  if [ "$retention_days" -gt 0 ] 2>/dev/null; then
    local -a remaining=()
    for f in "${candidates[@]}"; do
      if [ "$(find "$f" -maxdepth 0 -mtime +"$retention_days" -print 2>/dev/null)" ]; then
        local sz
        sz=$(stat -c%s "$f" 2>/dev/null) || sz=0
        rm -f "$f" "${f}.lock"
        PRUNE_DELETED=$((PRUNE_DELETED + 1))
        PRUNE_FREED_BYTES=$((PRUNE_FREED_BYTES + sz))
      else
        remaining+=("$f")
      fi
    done
    candidates=("${remaining[@]+"${remaining[@]}"}")
  fi

  # Phase 2: count cap — sort by mtime, delete oldest beyond max_sessions
  if [ "$max_sessions" -gt 0 ] 2>/dev/null; then
    local count=${#candidates[@]}
    if [ "$count" -gt "$max_sessions" ]; then
      # Sort by mtime (oldest first)
      local -a sorted=()
      while IFS= read -r -d '' f; do
        sorted+=("$f")
      done < <(printf '%s\0' "${candidates[@]}" | xargs -0 ls -t 2>/dev/null | tac | tr '\n' '\0')
      local to_delete=$((count - max_sessions))
      local i=0
      for f in "${sorted[@]}"; do
        [ "$i" -lt "$to_delete" ] || break
        local sz
        sz=$(stat -c%s "$f" 2>/dev/null) || sz=0
        rm -f "$f" "${f}.lock"
        PRUNE_DELETED=$((PRUNE_DELETED + 1))
        PRUNE_FREED_BYTES=$((PRUNE_FREED_BYTES + sz))
        i=$((i + 1))
      done
    fi
  fi

  # When both thresholds are 0: delete all candidates
  if [ "${retention_days:-0}" = "0" ] && [ "${max_sessions:-0}" = "0" ]; then
    for f in "${candidates[@]}"; do
      local sz
      sz=$(stat -c%s "$f" 2>/dev/null) || sz=0
      rm -f "$f" "${f}.lock"
      PRUNE_DELETED=$((PRUNE_DELETED + 1))
      PRUNE_FREED_BYTES=$((PRUNE_FREED_BYTES + sz))
    done
  fi
}
