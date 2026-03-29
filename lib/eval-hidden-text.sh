#!/usr/bin/env bash
# shellcheck disable=SC2034  # HIDDEN_TEXT_PASSED, HIDDEN_TEXT_DECISION, HIDDEN_TEXT_REASON set here, read externally via indirection
# Tier 3: HiddenText evaluator — detects CSS-hidden text, ANSI escapes, HTML injection markers
# Complements eval-codediff.sh (which handles invisible Unicode chars)

HIDDEN_TEXT_PASSED=true
HIDDEN_TEXT_REASON=""
HIDDEN_TEXT_DECISION="deny"

hidden_text_eval() {
  local tool_name="$1"
  local tool_input="$2"
  HIDDEN_TEXT_PASSED=true
  HIDDEN_TEXT_REASON="Passed"
  HIDDEN_TEXT_DECISION="deny"

  # Only check mutation tools — Write, Edit, Bash (content generation)
  case "$tool_name" in
    Write|Edit|Bash) ;;
    *) return 0 ;;
  esac

  # Resolve config: use pre-extracted _CFG_HT_* vars or fall back to jq
  local _ht_ansi_enabled _ht_css_enabled _ht_html_enabled
  local _ht_ansi_decision _ht_css_decision _ht_html_decision

  if [ -n "${_CFG_HT_ANSI_ENABLED+x}" ]; then
    # Pre-extracted path (handler mega-jq)
    _ht_ansi_enabled="$_CFG_HT_ANSI_ENABLED"
    _ht_css_enabled="$_CFG_HT_CSS_ENABLED"
    _ht_html_enabled="$_CFG_HT_HTML_ENABLED"
    _ht_ansi_decision="$_CFG_HT_ANSI_DECISION"
    _ht_css_decision="$_CFG_HT_CSS_DECISION"
    _ht_html_decision="$_CFG_HT_HTML_DECISION"
  else
    # Fallback: read from config file (standalone testing / no handler)
    local config="$LANEKEEP_CONFIG_FILE"
    if [ ! -f "$config" ]; then
      return 0
    fi
    local _ht
    _ht=$(jq -c '.evaluators.hidden_text // {}' "$config" 2>/dev/null) || return 0

    if [ "$(printf '%s' "$_ht" | jq -r 'if .enabled == false then "false" else "true" end')" = "false" ]; then
      HIDDEN_TEXT_REASON="HiddenText evaluator disabled"
      return 0
    fi

    _ht_ansi_enabled=$(printf '%s' "$_ht" | jq -r 'if .ansi.enabled == false then "false" else "true" end')
    _ht_css_enabled=$(printf '%s' "$_ht" | jq -r 'if .css_hiding.enabled == false then "false" else "true" end')
    _ht_html_enabled=$(printf '%s' "$_ht" | jq -r 'if .html_injection.enabled == false then "false" else "true" end')
    _ht_ansi_decision=$(printf '%s' "$_ht" | jq -r '.ansi.decision // "deny"')
    _ht_css_decision=$(printf '%s' "$_ht" | jq -r '.css_hiding.decision // "ask"')
    _ht_html_decision=$(printf '%s' "$_ht" | jq -r '.html_injection.decision // "ask"')

    # For fallback path, extract patterns as RS-delimited and store in the same vars
    _CFG_HT_ANSI_PATTERNS=$(printf '%s' "$_ht" | jq -r '[.ansi.patterns[]? // empty] | join("\u001e")')
    _CFG_HT_CSS_PATTERNS=$(printf '%s' "$_ht" | jq -r '[.css_hiding.patterns[]? // empty] | join("\u001e")')
    _CFG_HT_HTML_PATTERNS=$(printf '%s' "$_ht" | jq -r '[.html_injection.patterns[]? // empty] | join("\u001e")')
  fi

  # --- ANSI escape sequences ---
  if [ "$_ht_ansi_enabled" != "false" ]; then
    # Check for literal ESC byte (0x1b) in tool input
    if printf '%s' "$tool_input" | grep -qP '\x1b\[' 2>/dev/null; then
      HIDDEN_TEXT_PASSED=false
      HIDDEN_TEXT_DECISION="$_ht_ansi_decision"
      HIDDEN_TEXT_REASON="[LaneKeep] DENIED by HiddenTextEvaluator (Tier 3, score: 0.9)\nANSI escape sequence detected in content\nThese can hide text from human review while remaining visible to LLMs\nCompliance: CWE-1007"
      return 1
    fi
    # Also check for escaped representations that would produce ANSI codes
    if [ -n "${_CFG_HT_ANSI_PATTERNS:-}" ]; then
      local _ansi_pats
      IFS=$'\x1e' read -ra _ansi_pats <<< "$_CFG_HT_ANSI_PATTERNS"
      for pattern in "${_ansi_pats[@]}"; do
        [ -z "$pattern" ] && continue
        if printf '%s' "$tool_input" | timeout 1 grep -qP "$pattern" 2>/dev/null; then
          HIDDEN_TEXT_PASSED=false
          HIDDEN_TEXT_DECISION="$_ht_ansi_decision"
          HIDDEN_TEXT_REASON="[LaneKeep] DENIED by HiddenTextEvaluator (Tier 3, score: 0.9)\nANSI escape pattern detected: ${pattern}\nCompliance: CWE-1007"
          return 1
        fi
      done
    fi
  fi

  # --- CSS hidden text patterns ---
  if [ "$_ht_css_enabled" != "false" ]; then
    if [ -n "${_CFG_HT_CSS_PATTERNS:-}" ]; then
      local _css_pats
      IFS=$'\x1e' read -ra _css_pats <<< "$_CFG_HT_CSS_PATTERNS"
      for pattern in "${_css_pats[@]}"; do
        [ -z "$pattern" ] && continue
        if printf '%s' "$tool_input" | timeout 1 grep -qiP "$pattern" 2>/dev/null; then
          HIDDEN_TEXT_PASSED=false
          HIDDEN_TEXT_DECISION="$_ht_css_decision"
          HIDDEN_TEXT_REASON="[LaneKeep] DENIED by HiddenTextEvaluator (Tier 3, score: 0.8)\nCSS hidden text pattern detected: ${pattern}\nCSS properties can make text invisible to humans while LLMs still read it\nCompliance: CWE-1007, OWASP A05:2025"
          return 1
        fi
      done
    fi
  fi

  # --- HTML injection markers ---
  if [ "$_ht_html_enabled" != "false" ]; then
    if [ -n "${_CFG_HT_HTML_PATTERNS:-}" ]; then
      local _html_pats
      IFS=$'\x1e' read -ra _html_pats <<< "$_CFG_HT_HTML_PATTERNS"
      for pattern in "${_html_pats[@]}"; do
        [ -z "$pattern" ] && continue
        if printf '%s' "$tool_input" | timeout 1 grep -qiP "$pattern" 2>/dev/null; then
          HIDDEN_TEXT_PASSED=false
          HIDDEN_TEXT_DECISION="$_ht_html_decision"
          HIDDEN_TEXT_REASON="[LaneKeep] DENIED by HiddenTextEvaluator (Tier 3, score: 0.85)\nHTML injection pattern detected: ${pattern}\nHTML elements can carry hidden instructions invisible in rendered output\nCompliance: CWE-1007, CWE-79"
          return 1
        fi
      done
    fi
  fi

  return 0
}
