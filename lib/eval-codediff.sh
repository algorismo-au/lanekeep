#!/usr/bin/env bash
# shellcheck disable=SC2034  # CODEDIFF_PASSED, CODEDIFF_DECISION, CODEDIFF_REASON set here, read externally via indirection
# Tier 2: Static analysis on mutation tools (Bash, Write, Edit, Read)

CODEDIFF_PASSED=true
CODEDIFF_REASON=""
CODEDIFF_DECISION="deny"  # "deny" or "ask"

MUTATION_TOOLS="Bash Write Edit"
SENSITIVE_PATH_TOOLS="Bash Write Edit Read"

# Iterate a newline-separated pattern list and match each (lowercased) against
# the caller's $input_str (lowercased tool input) using grep -F. On the first
# match set CODEDIFF_PASSED=false, CODEDIFF_DECISION=$3 (default "deny"), and
# CODEDIFF_REASON built from $2 with the literal placeholder %PAT% replaced by
# the matched pattern. Returns 1 on match, 0 otherwise. Relies on bash dynamic
# scoping to read $input_str from the calling function's locals.
_cd_check_grepf() {
  local list="$1" reason_tpl="$2" decision="${3:-deny}"
  local pattern lower_pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    lower_pattern=$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$input_str" | grep -qF -- "$lower_pattern"; then
      CODEDIFF_PASSED=false
      CODEDIFF_DECISION="$decision"
      CODEDIFF_REASON="${reason_tpl//%PAT%/$pattern}"
      return 1
    fi
  done <<< "$list"
  return 0
}

# Iterate a newline-separated regex list and match each against $input_str via
# `timeout 1 grep -qP`. Enforces the caller's cumulative PCRE budget
# ($_cd_pcre_start / $_cd_pcre_budget). On match set CODEDIFF_PASSED=false,
# CODEDIFF_DECISION=$3, CODEDIFF_REASON=$2 (no pattern interpolation — regex
# reasons in the caller don't quote the source pattern). Returns 1 on match or
# budget-exceeded, 0 otherwise. Dynamic-scoped locals like _cd_check_grepf.
_cd_check_grepp() {
  local list="$1" reason="$2" decision="${3:-deny}"
  local pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    if (( ${EPOCHSECONDS:-$(date +%s)} - _cd_pcre_start >= _cd_pcre_budget )); then
      CODEDIFF_PASSED=false
      CODEDIFF_REASON="[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2)\nPCRE timeout budget exceeded (${_cd_pcre_budget}s cumulative)"
      return 1
    fi
    if printf '%s' "$input_str" | timeout 1 grep -qP "$pattern" 2>/dev/null; then
      CODEDIFF_PASSED=false
      CODEDIFF_DECISION="$decision"
      CODEDIFF_REASON="$reason"
      return 1
    fi
  done <<< "$list"
  return 0
}

codediff_eval() {
  local tool_name="$1"
  local tool_input="$2"
  CODEDIFF_PASSED=true
  CODEDIFF_REASON="Passed"
  CODEDIFF_DECISION="deny"

  # Cumulative PCRE timeout budget — deny if pattern scanning takes too long
  local _cd_pcre_start _cd_pcre_budget=5
  _cd_pcre_start="${EPOCHSECONDS:-$(date +%s)}"

  local config="$LANEKEEP_CONFIG_FILE"
  if [ ! -f "$config" ]; then
    return 0
  fi

  # Extract codediff section once (57KB config → ~1KB section)
  local _cd
  _cd=$(jq -c '.evaluators.codediff // {}' "$config" 2>/dev/null) || return 0

  # Check if evaluator is disabled
  if [ "$(printf '%s' "$_cd" | jq -r 'if .enabled == false then "false" else "true" end')" = "false" ]; then
    CODEDIFF_REASON="CodeDiff evaluator disabled"
    return 0
  fi

  # Short-circuit for excluded file extensions (e.g. *.md tutorial content)
  if declare -F should_skip_by_extension > /dev/null \
     && should_skip_by_extension "$tool_name" "$tool_input" "codediff"; then
    CODEDIFF_REASON="Skipped: file extension excluded from codediff"
    return 0
  fi

  # Extract all pattern arrays in a single jq call (9→1 subprocess)
  local _CD_SENSITIVE_PATHS="" _CD_PROTECTED_DIRS="" _CD_SAFE_EXCEPTIONS=""
  local _CD_SECRET_PATTERNS="" _CD_DESTRUCTIVE_PATTERNS="" _CD_DANGEROUS_GIT_PATTERNS=""
  local _CD_DENY_PATTERNS="" _CD_ASK_PATTERNS="" _CD_HIDDEN_CHARS_PATTERNS=""
  local _CD_HIDDEN_CHARS_ENABLED="true"
  local _CD_DESTRUCTIVE_REGEX="" _CD_DANGEROUS_GIT_REGEX=""
  local _CD_HOMOGLYPH_PATTERNS="" _CD_HOMOGLYPH_ENABLED="true"
  local _CD_ENCODING_PATTERNS="" _CD_ENCODING_ENABLED="true" _CD_ENCODING_REASON=""
  eval "$(printf '%s' "$_cd" | jq -r '
    "_CD_SENSITIVE_PATHS=" + ([.sensitive_paths[]?] | join("\n") | @sh),
    "_CD_PROTECTED_DIRS=" + ([.protected_dirs[]?] | join("\n") | @sh),
    "_CD_SAFE_EXCEPTIONS=" + ([(.safe_exceptions // [])[] | [(.command_contains // ""), (.target_contains // ""), (.reason // "Safe exception")] | @tsv] | join("\n") | @sh),
    "_CD_SECRET_PATTERNS=" + ([.secret_patterns[]?] | join("\n") | @sh),
    "_CD_DESTRUCTIVE_PATTERNS=" + ([.destructive_patterns[]?] | join("\n") | @sh),
    "_CD_DANGEROUS_GIT_PATTERNS=" + ([.dangerous_git_patterns[]?] | join("\n") | @sh),
    "_CD_DENY_PATTERNS=" + ([.deny_patterns[]?] | join("\n") | @sh),
    "_CD_ASK_PATTERNS=" + ([.ask_patterns[]?] | join("\n") | @sh),
    "_CD_HIDDEN_CHARS_PATTERNS=" + ([.hidden_chars.patterns[]?] | join("\n") | @sh),
    "_CD_HIDDEN_CHARS_ENABLED=" + (if .hidden_chars.enabled == false then "false" else "true" end | @sh),
    "_CD_DESTRUCTIVE_REGEX=" + ([.destructive_regex[]?] | join("\n") | @sh),
    "_CD_DANGEROUS_GIT_REGEX=" + ([.dangerous_git_regex[]?] | join("\n") | @sh),
    "_CD_HOMOGLYPH_PATTERNS=" + ([.homoglyphs.patterns[]?] | join("\n") | @sh),
    "_CD_HOMOGLYPH_ENABLED=" + (if .homoglyphs.enabled == false then "false" else "true" end | @sh),
    "_CD_ENCODING_PATTERNS=" + ([.encoding_detection.patterns[]?] | join("\n") | @sh),
    "_CD_ENCODING_ENABLED=" + (if .encoding_detection.enabled == false then "false" else "true" end | @sh),
    "_CD_ENCODING_REASON=" + ((.encoding_detection.reason // "Encoded content detected — may hide payload; verify this is intentional") | @sh)
  ')" || true

  local input_str
  input_str=$(printf '%s' "$tool_input" | tr '[:upper:]' '[:lower:]')

  # --- Sensitive path checks (applies to read and write tools) ---
  case " $SENSITIVE_PATH_TOOLS " in
    *" $tool_name "*)
      _cd_check_grepf "$_CD_SENSITIVE_PATHS" \
        "[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nSensitive path accessed: '%PAT%'\nSuggestion: Do not read or modify sensitive files" \
        || return 1
      ;;
  esac

  # --- Protected directory checks (applies to write tools) ---
  case " $MUTATION_TOOLS " in
    *" $tool_name "*)
      _cd_check_grepf "$_CD_PROTECTED_DIRS" \
        "[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nProtected directory: '%PAT%'\nSuggestion: CI/CD and infrastructure files require manual changes" \
        || return 1
      ;;
  esac

  # Skip remaining checks for read-only tools
  case " $MUTATION_TOOLS " in
    *" $tool_name "*)  ;;
    *)
      CODEDIFF_REASON="Read-only tool, skipped"
      return 0
      ;;
  esac

  # --- Safe exceptions (single jq call with @tsv instead of O(3n+1) calls) ---
  local cmd_contains target_contains exc_reason
  while IFS=$'\t' read -r cmd_contains target_contains exc_reason; do
    [ -z "$cmd_contains" ] && continue
    [ -z "$target_contains" ] && continue
    local lower_cmd lower_target
    lower_cmd=$(printf '%s' "$cmd_contains" | tr '[:upper:]' '[:lower:]')
    lower_target=$(printf '%s' "$target_contains" | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$input_str" | grep -qF -- "$lower_cmd"; then
      if printf '%s' "$input_str" | grep -qF -- "$lower_target"; then
        CODEDIFF_REASON="${exc_reason:-Safe exception}"
        return 0
      fi
    fi
  done <<< "$_CD_SAFE_EXCEPTIONS"

  # --- Secret patterns → deny ---
  _cd_check_grepf "$_CD_SECRET_PATTERNS" \
    "[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nSecret pattern detected: '%PAT%'\nSuggestion: Remove secrets from code, use environment variables" \
    || return 1

  # --- Destructive patterns → deny ---
  _cd_check_grepf "$_CD_DESTRUCTIVE_PATTERNS" \
    "[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nDestructive pattern detected: '%PAT%'\nSuggestion: Use safer alternatives" \
    || return 1

  # --- Destructive regex patterns → deny (flag-reordering-aware) ---
  _cd_check_grepp "$_CD_DESTRUCTIVE_REGEX" \
    "[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nDestructive pattern detected (regex)\nSuggestion: Use safer alternatives" \
    || return 1

  # --- Dangerous git patterns → deny ---
  _cd_check_grepf "$_CD_DANGEROUS_GIT_PATTERNS" \
    "[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nDangerous git operation detected: '%PAT%'\nSuggestion: Use non-destructive git operations" \
    || return 1

  # --- Dangerous git regex patterns → deny (flag-reordering-aware) ---
  _cd_check_grepp "$_CD_DANGEROUS_GIT_REGEX" \
    "[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nDangerous git operation detected (regex)\nSuggestion: Use non-destructive git operations" \
    || return 1

  # --- Additional deny patterns → deny ---
  _cd_check_grepf "$_CD_DENY_PATTERNS" \
    "[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nBlocked pattern detected: '%PAT%'\nSuggestion: This operation is not permitted" \
    || return 1

  # --- Ask patterns → ask (escalate to user) ---
  _cd_check_grepf "$_CD_ASK_PATTERNS" \
    "[LaneKeep] NEEDS APPROVAL — CodeDiffEvaluator (Tier 2)\nPattern matched: '%PAT%'\nThis operation requires user confirmation" \
    "ask" \
    || return 1

  # --- Encoding detection → ask (pre-execution) ---
  # Detects base64 decode pipes, hex escape sequences, nested decode-to-eval
  # chains, and dense URL-encoded payloads before execution. Uses PCRE with
  # timeout to guard against ReDoS.
  if [ "$_CD_ENCODING_ENABLED" != "false" ]; then
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      if (( ${EPOCHSECONDS:-$(date +%s)} - _cd_pcre_start >= _cd_pcre_budget )); then
        CODEDIFF_PASSED=false
        CODEDIFF_REASON="[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2)\nPCRE timeout budget exceeded (${_cd_pcre_budget}s cumulative)"
        return 1
      fi
      if printf '%s' "$tool_input" | timeout 1 grep -qP -- "$pattern" 2>/dev/null; then
        local match_snippet
        match_snippet=$(printf '%s' "$tool_input" | timeout 1 grep -oP -- "$pattern" 2>/dev/null | head -1 | head -c 80)
        CODEDIFF_PASSED=false
        CODEDIFF_DECISION="ask"
        CODEDIFF_REASON="[LaneKeep] NEEDS APPROVAL — CodeDiffEvaluator (Tier 2, score: 0.8)\n${_CD_ENCODING_REASON}\nMatched: ${match_snippet:-encoded content}\nCompliance: MITRE ATT&CK T1027, ATLAS T0015"
        return 1
      fi
    done <<< "$_CD_ENCODING_PATTERNS"
  fi

  # --- Hidden Unicode character detection → deny ---
  # Scans Write/Edit tool input for invisible/bidirectional Unicode characters
  # that can be used for trojan-source attacks or content smuggling.
  # Uses PCRE (grep -P) to match Unicode codepoints in the raw tool input.
  if [ "$_CD_HIDDEN_CHARS_ENABLED" != "false" ]; then
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      if (( ${EPOCHSECONDS:-$(date +%s)} - _cd_pcre_start >= _cd_pcre_budget )); then
        CODEDIFF_PASSED=false
        CODEDIFF_REASON="[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2)\nPCRE timeout budget exceeded (${_cd_pcre_budget}s cumulative)"
        return 1
      fi
      if printf '%s' "$tool_input" | timeout 1 grep -qP -- "$pattern" 2>/dev/null; then
        local char_desc
        char_desc=$(printf '%s' "$tool_input" | timeout 1 grep -oP -- "$pattern" 2>/dev/null | head -1 | od -A n -t x1 | tr -d ' \n')
        CODEDIFF_PASSED=false
        CODEDIFF_REASON="[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2, score: 0.9)\nHidden Unicode character detected (bytes: ${char_desc:-unknown})\nSuggestion: Remove invisible/bidirectional Unicode characters — these can be used for trojan-source or content-smuggling attacks"
        return 1
      fi
    done <<< "$_CD_HIDDEN_CHARS_PATTERNS"
  fi

  # --- Homoglyph detection → ask ---
  # Detects Cyrillic/Greek characters mixed into Latin text (visual spoofing).
  # Attackers use lookalike characters (e.g. Cyrillic а U+0430 vs Latin a) to
  # smuggle instructions past text-based filters while remaining LLM-readable.
  if [ "$_CD_HOMOGLYPH_ENABLED" != "false" ]; then
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      if (( ${EPOCHSECONDS:-$(date +%s)} - _cd_pcre_start >= _cd_pcre_budget )); then
        CODEDIFF_PASSED=false
        CODEDIFF_REASON="[LaneKeep] DENIED by CodeDiffEvaluator (Tier 2)\nPCRE timeout budget exceeded (${_cd_pcre_budget}s cumulative)"
        return 1
      fi
      if printf '%s' "$tool_input" | timeout 1 grep -qP -- "$pattern" 2>/dev/null; then
        local glyph_desc
        glyph_desc=$(printf '%s' "$tool_input" | timeout 1 grep -oP -- "$pattern" 2>/dev/null | head -1 | od -A n -t x1 | tr -d ' \n')
        CODEDIFF_PASSED=false
        CODEDIFF_DECISION="ask"
        CODEDIFF_REASON="[LaneKeep] NEEDS APPROVAL — CodeDiffEvaluator (Tier 2, score: 0.8)\nHomoglyph character detected (bytes: ${glyph_desc:-unknown})\nCyrillic/Greek characters mixed with Latin text can be used for visual spoofing attacks\nCompliance: CWE-1007"
        return 1
      fi
    done <<< "$_CD_HOMOGLYPH_PATTERNS"
  fi

  return 0
}
