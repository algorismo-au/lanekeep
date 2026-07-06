#!/usr/bin/env bash
# shellcheck disable=SC2034  # PYTHON_EXEC_* set here, read externally via indirection
# Tier 2.2: Python Exec Fragmentation evaluator
# Detects subprocess.*/os.system/shell=True calls whose arguments are dynamically constructed

PYTHON_EXEC_PASSED=true
PYTHON_EXEC_REASON=""
PYTHON_EXEC_DECISION="deny"
PYTHON_EXEC_HINT=""
PYTHON_EXEC_SUBTYPE=""

python_exec_eval() {
  local tool_name="$1"
  local tool_input="$2"
  PYTHON_EXEC_PASSED=true
  PYTHON_EXEC_REASON="Passed"
  PYTHON_EXEC_DECISION="deny"
  PYTHON_EXEC_HINT=""
  PYTHON_EXEC_SUBTYPE=""

  # Only Write/Edit — mutation tools that produce .py source
  case "$tool_name" in
    Write|Edit) ;;
    *) return 0 ;;
  esac

  # Resolve config: use pre-extracted _CFG_PYTHON_EXEC_* vars or fall back to jq
  local _apis _frag_pats _window _shell_dec _frag_dec _chr_dec
  if [ -n "${_CFG_PYTHON_EXEC_ENABLED+x}" ]; then
    if [ "$_CFG_PYTHON_EXEC_ENABLED" = "false" ]; then
      return 0
    fi
    _apis="${_CFG_PYTHON_EXEC_APIS:-}"
    _frag_pats="${_CFG_PYTHON_EXEC_FRAG_PATTERNS:-}"
    _window="${_CFG_PYTHON_EXEC_WINDOW:-10}"
    _shell_dec="${_CFG_PYTHON_EXEC_SHELL_TRUE_DECISION:-warn}"
    _frag_dec="${_CFG_PYTHON_EXEC_FRAG_DECISION:-ask}"
    _chr_dec="${_CFG_PYTHON_EXEC_CHR_CHAIN_DECISION:-deny}"
  else
    local config="${LANEKEEP_CONFIG_FILE:-}"
    if [ -z "$config" ] || [ ! -f "$config" ]; then
      return 0
    fi
    local _pe
    _pe=$(jq -c '.evaluators.python_exec // {}' "$config" 2>/dev/null) || return 0
    if [ "$(printf '%s' "$_pe" | jq -r 'if .enabled == false then "false" else "true" end')" = "false" ]; then
      return 0
    fi
    _apis=$(printf '%s' "$_pe" | jq -r '[.exec_apis[]? // empty] | join("")')
    _frag_pats=$(printf '%s' "$_pe" | jq -r '[.fragmentation_patterns[]? // empty] | join("")')
    _window=$(printf '%s' "$_pe" | jq -r '.fragmentation_window // 10')
    _shell_dec=$(printf '%s' "$_pe" | jq -r '.shell_true_decision // "warn"')
    _frag_dec=$(printf '%s' "$_pe" | jq -r '.fragmentation_decision // "ask"')
    _chr_dec=$(printf '%s' "$_pe" | jq -r '.chr_chain_decision // "deny"')
  fi

  # Only .py files
  local file_path
  file_path=$(printf '%s' "$tool_input" | jq -r '.file_path // ""' 2>/dev/null) || file_path=""
  case "$file_path" in
    *.py) ;;
    *) return 0 ;;
  esac

  # Extract content (Write uses .content, Edit uses .new_string)
  local content
  content=$(printf '%s' "$tool_input" | jq -r '.content // .new_string // ""' 2>/dev/null) || content=""
  [ -z "$content" ] && return 0
  [ ${#content} -gt 1048576 ] && return 0

  # Build combined regex for exec_apis (alt-branches joined with |)
  local _apis_arr _api_regex=""
  IFS=$'\x1e' read -ra _apis_arr <<< "$_apis"
  local _a
  for _a in "${_apis_arr[@]}"; do
    [ -z "$_a" ] && continue
    if [ -z "$_api_regex" ]; then _api_regex="$_a"; else _api_regex="$_api_regex|$_a"; fi
  done

  # Find exec_api line numbers (grep -n gives "N:...")
  local -a exec_lines=()
  if [ -n "$_api_regex" ]; then
    mapfile -t exec_lines < <(printf '%s\n' "$content" | timeout 1 grep -nP "$_api_regex" 2>/dev/null | cut -d: -f1)
  fi

  # shell=True presence anywhere
  local has_shell_true=false
  if printf '%s' "$content" | timeout 1 grep -qP 'shell\s*=\s*True' 2>/dev/null; then
    has_shell_true=true
  fi

  # No exec_api match — shell=True only → warn, else pass
  if [ ${#exec_lines[@]} -eq 0 ]; then
    if [ "$has_shell_true" = true ]; then
      PYTHON_EXEC_PASSED=false
      PYTHON_EXEC_SUBTYPE="shell_true"
      PYTHON_EXEC_DECISION="$_shell_dec"
      PYTHON_EXEC_REASON="[LaneKeep] WARN by PythonExec (Tier 2.2, score: 0.4)\nshell=True detected in Python content"
      PYTHON_EXEC_HINT="WARN: shell=True enables command injection. Prefer list-form subprocess.run([...]) with shell=False."
      return 1
    fi
    return 0
  fi

  # Build fragmentation regex
  local _frag_arr _frag_regex=""
  IFS=$'\x1e' read -ra _frag_arr <<< "$_frag_pats"
  local _f
  for _f in "${_frag_arr[@]}"; do
    [ -z "$_f" ] && continue
    if [ -z "$_frag_regex" ]; then _frag_regex="$_f"; else _frag_regex="$_frag_regex|$_f"; fi
  done

  # Find fragmentation and chr_chain line numbers
  local -a frag_lines=() chr_lines=()
  if [ -n "$_frag_regex" ]; then
    mapfile -t frag_lines < <(printf '%s\n' "$content" | timeout 1 grep -nP "$_frag_regex" 2>/dev/null | cut -d: -f1)
  fi
  mapfile -t chr_lines < <(printf '%s\n' "$content" | timeout 1 grep -nP 'chr\(\d+\)\s*\+\s*chr\(\d+\)\s*\+\s*chr\(' 2>/dev/null | cut -d: -f1)

  # chr_chain proximity check (highest severity — precedence over fragmentation)
  local exec_l chr_l frag_l diff
  for exec_l in "${exec_lines[@]}"; do
    for chr_l in "${chr_lines[@]}"; do
      diff=$((exec_l - chr_l))
      [ "$diff" -lt 0 ] && diff=$((-diff))
      if [ "$diff" -le "$_window" ]; then
        PYTHON_EXEC_PASSED=false
        PYTHON_EXEC_SUBTYPE="chr_chain"
        PYTHON_EXEC_DECISION="$_chr_dec"
        PYTHON_EXEC_REASON="[LaneKeep] DENIED by PythonExec (Tier 2.2, score: 0.95)\nchr()-chain obfuscation within ${_window} lines of exec_api\nExec line: ${exec_l}, chr chain line: ${chr_l}"
        PYTHON_EXEC_HINT="DENIED: subprocess argument assembled via chr(N)+chr(N) — obfuscation. Use literal arguments so LaneKeep can evaluate them."
        return 1
      fi
    done
  done

  # Fragmentation proximity check
  for exec_l in "${exec_lines[@]}"; do
    for frag_l in "${frag_lines[@]}"; do
      diff=$((exec_l - frag_l))
      [ "$diff" -lt 0 ] && diff=$((-diff))
      if [ "$diff" -le "$_window" ]; then
        PYTHON_EXEC_PASSED=false
        PYTHON_EXEC_SUBTYPE="fragmentation"
        PYTHON_EXEC_DECISION="$_frag_dec"
        PYTHON_EXEC_REASON="[LaneKeep] ESCALATED by PythonExec (Tier 2.2, score: 0.75)\nDynamic argument assembly within ${_window} lines of exec_api\nExec line: ${exec_l}, assembly line: ${frag_l}"
        PYTHON_EXEC_HINT="DENIED: subprocess argument assembled via dynamic construction. Confirm intentional or use a literal LaneKeep can evaluate."
        return 1
      fi
    done
  done

  # exec_api present without fragmentation — if shell=True somewhere, warn
  if [ "$has_shell_true" = true ]; then
    PYTHON_EXEC_PASSED=false
    PYTHON_EXEC_SUBTYPE="shell_true"
    PYTHON_EXEC_DECISION="$_shell_dec"
    PYTHON_EXEC_REASON="[LaneKeep] WARN by PythonExec (Tier 2.2, score: 0.4)\nshell=True detected with exec_api"
    PYTHON_EXEC_HINT="WARN: shell=True enables command injection. Prefer list-form subprocess.run([...]) with shell=False."
    return 1
  fi

  return 0
}
