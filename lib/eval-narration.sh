#!/usr/bin/env bash
# shellcheck disable=SC2034  # NARRATION_* set here, read externally via indirection
# Tier 3.1: Narration evaluator — scans tool_input for agent-output confession keywords
# Complements hardblock (T1) and python_exec (T2.2) by detecting on-record evasion narration

NARRATION_PASSED=true
NARRATION_REASON=""
NARRATION_DECISION="ask"
NARRATION_HINT=""

# Approximate glob matching: converts ** to * (loses depth semantics, close enough for whitelist_paths)
_narration_path_matches() {
  local path="$1" pattern="$2"
  pattern="${pattern//\*\*/*}"
  # shellcheck disable=SC2053
  [[ "$path" == $pattern ]]
}

narration_eval() {
  local tool_name="$1"
  local tool_input="$2"
  NARRATION_PASSED=true
  NARRATION_REASON="Passed"
  NARRATION_DECISION="ask"
  NARRATION_HINT=""

  # Only content-carrying tools
  case "$tool_name" in
    Write|Edit|Bash|Task) ;;
    *) return 0 ;;
  esac

  # Resolve config: use pre-extracted _CFG_NARRATION_* vars or fall back to jq
  local _n_patterns _n_whitelist_paths _n_decision
  if [ -n "${_CFG_NARRATION_ENABLED+x}" ]; then
    if [ "$_CFG_NARRATION_ENABLED" = "false" ]; then
      return 0
    fi
    _n_patterns="${_CFG_NARRATION_PATTERNS:-}"
    _n_whitelist_paths="${_CFG_NARRATION_WHITELIST_PATHS:-}"
    _n_decision="${_CFG_NARRATION_DECISION:-ask}"
  else
    local config="${LANEKEEP_CONFIG_FILE:-}"
    if [ -z "$config" ] || [ ! -f "$config" ]; then
      return 0
    fi
    local _n
    _n=$(jq -c '.evaluators.narration // {}' "$config" 2>/dev/null) || return 0
    if [ "$(printf '%s' "$_n" | jq -r 'if .enabled == false then "false" else "true" end')" = "false" ]; then
      return 0
    fi
    _n_patterns=$(printf '%s' "$_n" | jq -r '[.patterns[]? // empty] | join("")')
    _n_whitelist_paths=$(printf '%s' "$_n" | jq -r '[.whitelist_paths[]? // empty] | join("")')
    _n_decision=$(printf '%s' "$_n" | jq -r '.decision // "ask"')
  fi

  [ -z "$_n_patterns" ] && return 0
  [ -z "$_n_decision" ] && _n_decision="ask"

  # Extract file_path if present, apply path-only whitelist
  local file_path
  file_path=$(printf '%s' "$tool_input" | jq -r '.file_path // ""' 2>/dev/null) || file_path=""

  if [ -n "$file_path" ] && [ -n "$_n_whitelist_paths" ]; then
    local _wp_arr
    IFS=$'\x1e' read -ra _wp_arr <<< "$_n_whitelist_paths"
    local pat
    for pat in "${_wp_arr[@]}"; do
      [ -z "$pat" ] && continue
      if _narration_path_matches "$file_path" "$pat"; then
        return 0  # path-whitelisted
      fi
    done
  fi

  # Extract search content by tool
  local search_content=""
  case "$tool_name" in
    Write)
      search_content=$(printf '%s' "$tool_input" | jq -r '.content // ""' 2>/dev/null) || search_content=""
      ;;
    Edit)
      search_content=$(printf '%s' "$tool_input" | jq -r '.new_string // ""' 2>/dev/null) || search_content=""
      ;;
    Bash)
      search_content=$(printf '%s' "$tool_input" | jq -r '.command // ""' 2>/dev/null) || search_content=""
      ;;
    Task)
      search_content=$(printf '%s' "$tool_input" | jq -r '(.prompt // "") + " " + (.description // "")' 2>/dev/null) || search_content=""
      ;;
  esac

  [ -z "$search_content" ] && return 0
  # Content size limit — skip pathological payloads
  [ ${#search_content} -gt 1048576 ] && return 0

  # Iterate patterns, match against content
  local _p_arr
  IFS=$'\x1e' read -ra _p_arr <<< "$_n_patterns"
  local pattern _matched
  for pattern in "${_p_arr[@]}"; do
    [ -z "$pattern" ] && continue
    _matched=$(printf '%s' "$search_content" | timeout 1 grep -oiP "$pattern" 2>/dev/null | head -1) || true
    if [ -n "$_matched" ]; then
      NARRATION_PASSED=false
      NARRATION_DECISION="$_n_decision"
      NARRATION_REASON="[LaneKeep] DENIED by Narration (Tier 3.1, score: 0.85)\nEvasion keyword '$_matched' detected in $tool_name content\nCompliance: agent-evasion-detection"
      NARRATION_HINT="DENIED: agent output contains evasion keyword '$_matched'. Reformulate the change without workaround language."
      return 1
    fi
  done

  return 0
}
