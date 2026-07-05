#!/usr/bin/env bash
# Headless escalation sink — when LANEKEEP_HEADLESS=1, rewrite `ask` decisions
# to `deny` and persist the asked-about context as .lanekeep/escalations/<id>.json
# so a parent runtime (shipper, CI) can act on it after the agent exits.
#
# Spec: specs/HEADLESS-ESCALATION-SINK.md (in buildinglanekeep meta-repo)

# True when this invocation is running unattended (no human to answer ask).
# Accepts 1 | true | yes (case-insensitive) — cron env files vary in convention.
headless::is_active() {
  case "${LANEKEEP_HEADLESS:-}" in
    1|true|TRUE|True|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve the escalation id (basename without .json).
# Order: $LANEKEEP_TASK_ID, then session id, then "unattached-<epoch>".
headless::escalation_id() {
  local sid="${1:-}"
  if [ -n "${LANEKEEP_TASK_ID:-}" ]; then
    printf '%s' "$LANEKEEP_TASK_ID"
  elif [ -n "$sid" ]; then
    printf '%s' "$sid"
  else
    printf 'unattached-%s' "$(date +%s)"
  fi
}

# Resolve the escalation directory.
# Order: $LANEKEEP_ESCALATION_DIR, then $_CFG_HEADLESS_DIR, then default.
headless::escalation_dir() {
  if [ -n "${LANEKEEP_ESCALATION_DIR:-}" ]; then
    printf '%s' "$LANEKEEP_ESCALATION_DIR"
  elif [ -n "${_CFG_HEADLESS_DIR:-}" ]; then
    printf '%s' "$_CFG_HEADLESS_DIR"
  else
    printf '%s' "${PROJECT_DIR:-.}/.lanekeep/escalations"
  fi
}

headless::escalation_path() {
  local sid="${1:-}"
  printf '%s/%s.json' "$(headless::escalation_dir)" "$(headless::escalation_id "$sid")"
}

# Tail the last N entries of the session trace JSONL.
# Returns a JSON array on stdout (empty array if no trace).
# Each entry is a compact projection (ts, tool, decision, input_excerpt) to
# keep the bundle small and avoid forwarding redaction-sensitive fields.
headless::_trace_tail() {
  local sid="$1" n="${2:-20}"
  local trace="${PROJECT_DIR:-.}/.lanekeep/traces/${sid}.jsonl"
  [ -f "$trace" ] || { printf '[]'; return 0; }
  # tail -c bounds the read; jq -s . parses the slurped lines; .[-n:] picks the last N.
  tail -c 65536 "$trace" 2>/dev/null \
    | jq -sc --argjson n "$n" '
        [ .[-$n:][] | {
            ts: .timestamp,
            tool: .tool_name,
            decision: .decision,
            input_excerpt: (.tool_input | tostring | .[0:200])
          } ]
      ' 2>/dev/null || printf '[]'
}

# Assemble the bundle JSON.
# Args: session_id tool_name tool_input reason agent_hint tier_results_json
# tier_results_json is a JSON array string ("[" "{...}" "," ... "]") matching
# the shape of $RESULTS[@] in the handler.
headless::_build_bundle() {
  local sid="$1" tool="$2" tool_input="$3" reason="$4" hint="$5" results="$6"
  local trace_tail
  trace_tail=$(headless::_trace_tail "$sid" "${_CFG_HEADLESS_TAIL:-20}")

  local prev_count=0
  local out_path
  out_path=$(headless::escalation_path "$sid")
  if [ -f "$out_path" ]; then
    prev_count=$(jq -r '.escalation_count // 0' "$out_path" 2>/dev/null)
    [[ "$prev_count" =~ ^[0-9]+$ ]] || prev_count=0
  fi
  local next_count=$((prev_count + 1))

  jq -nc \
    --arg ts        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
    --arg task_id   "${LANEKEEP_TASK_ID:-}" \
    --arg sid       "$sid" \
    --argjson ec    "$next_count" \
    --arg tool      "$tool" \
    --argjson ti    "$tool_input" \
    --arg reason    "$reason" \
    --arg hint      "$hint" \
    --argjson tr    "$results" \
    --argjson tt    "$trace_tail" \
    --arg hl        "${LANEKEEP_HEADLESS:-}" \
    --arg lpid      "${LANEKEEP_LOOP_ID:-}" \
    '{
       schema_version: "1.0",
       task_id: $task_id,
       session_id: $sid,
       timestamp: $ts,
       escalation_count: $ec,
       tool_name: $tool,
       tool_input: $ti,
       original_decision: "ask",
       rewritten_to: "deny",
       reason: $reason,
       agent_hint: $hint,
       tier_results: [ $tr[] | select(.passed == false) ],
       trace_tail: $tt,
       env_snapshot: {
         LANEKEEP_HEADLESS:   $hl,
         LANEKEEP_TASK_ID:    $task_id,
         LANEKEEP_SESSION_ID: $sid,
         LANEKEEP_LOOP_ID:    $lpid
       }
     }
     | if $task_id == "" then del(.task_id) else . end
     | if $hint    == "" then del(.agent_hint) else . end
     | if $lpid    == "" then del(.env_snapshot.LANEKEEP_LOOP_ID) else . end'
}

# Best-effort write: never fails the caller, even when the dir is unwritable.
# Args: bundle_json session_id
headless::write_bundle() {
  local bundle="$1" sid="$2"
  local dir; dir=$(headless::escalation_dir)
  local out; out=$(headless::escalation_path "$sid")

  (umask 077; mkdir -p "$dir") 2>/dev/null || return 0
  printf '%s\n' "$bundle" > "${out}.tmp" 2>/dev/null && mv "${out}.tmp" "$out" 2>/dev/null
  return 0
}
