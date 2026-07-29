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

# Extract path-like tokens from a Bash command line for whitelist matching.
# Deliberately dumb: whitespace-split (no subshell/heredoc parsing), strip balanced
# surrounding quotes, drop flags/operators/pure-dot expressions. Prints one token per line.
_narration_bash_path_tokens() {
  local cmd="$1"
  local -a raw
  IFS=$' \t' read -ra raw <<< "$cmd"
  local w
  for w in "${raw[@]}"; do
    if [[ "$w" == \'*\' ]]; then w="${w#\'}"; w="${w%\'}"; fi
    if [[ "$w" == \"*\" ]]; then w="${w#\"}"; w="${w%\"}"; fi
    [ -z "$w" ] && continue
    [[ "$w" == -* ]] && continue
    case "$w" in
      '&&'|'||'|'|'|'>'|'<'|';'|'>>'|'<<'|'&') continue ;;
    esac
    if [[ "$w" == */* ]]; then
      printf '%s\n' "$w"
    elif [[ "$w" == .* ]]; then
      continue
    elif [[ "$w" == *.* ]]; then
      printf '%s\n' "$w"
    fi
  done
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

  # Bash-only: extend whitelist_paths to command path tokens (Write/Edit already handled above).
  # Skips only when ALL extracted path tokens match at least one whitelist pattern —
  # a mixed command (whitelisted + non-whitelisted paths) still falls through to pattern scan.
  if [ "$tool_name" = "Bash" ] && [ -n "$_n_whitelist_paths" ]; then
    local -a _bash_tokens
    mapfile -t _bash_tokens < <(_narration_bash_path_tokens "$search_content")
    if [ "${#_bash_tokens[@]}" -gt 0 ]; then
      local _wp_arr
      IFS=$'\x1e' read -ra _wp_arr <<< "$_n_whitelist_paths"
      local _tok _wp _all_matched=true _tok_matched
      for _tok in "${_bash_tokens[@]}"; do
        _tok_matched=false
        for _wp in "${_wp_arr[@]}"; do
          [ -z "$_wp" ] && continue
          if _narration_path_matches "$_tok" "$_wp"; then
            _tok_matched=true
            break
          fi
        done
        if [ "$_tok_matched" = false ]; then
          _all_matched=false
          break
        fi
      done
      if [ "$_all_matched" = true ]; then
        return 0
      fi
    fi
  fi

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
