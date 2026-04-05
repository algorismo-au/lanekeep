#!/usr/bin/env bash
# shellcheck disable=SC2034  # INPUT_PII_* globals set here, read externally via indirection
# Tier 4: Input PII evaluator — scans tool input for PII patterns

INPUT_PII_PASSED=true
INPUT_PII_REASON=""
INPUT_PII_DECISION="ask"        # "deny" | "ask" | "warn"
INPUT_PII_DETECTIONS="[]"       # JSON array of what was found
INPUT_PII_COMPLIANCE="[]"       # JSON array of compliance references

input_pii_eval() {
  local tool_name="$1"
  local tool_input="$2"
  INPUT_PII_PASSED=true
  INPUT_PII_REASON="Passed"
  INPUT_PII_DECISION="ask"
  INPUT_PII_DETECTIONS="[]"
  INPUT_PII_COMPLIANCE="[]"

  local config="$LANEKEEP_CONFIG_FILE"

  # Resolve config: use pre-extracted _CFG_INPUT_PII_* vars or fall back to jq
  local on_detect pii_patterns_raw all_compliance _has_custom_tools_filter pii_allowlist_raw

  if [ -n "${_CFG_INPUT_PII_ON_DETECT+x}" ]; then
    # Pre-extracted path (handler mega-jq)
    on_detect="$_CFG_INPUT_PII_ON_DETECT"
    pii_patterns_raw="$_CFG_INPUT_PII_PATTERNS"
    pii_allowlist_raw="${_CFG_INPUT_PII_ALLOWLIST:-}"
    all_compliance="$_CFG_INPUT_PII_COMPLIANCE"
    # Default tools filter (Write|Edit|Bash) — skip non-mutation tools
    # Use pre-extracted flag; custom tools filters need jq fallback (rare)
    _has_custom_tools_filter=""
    if [ "${_CFG_INPUT_PII_HAS_TOOLS:-false}" = "true" ]; then
      _has_custom_tools_filter="yes"
    elif [ -z "${_CFG_INPUT_PII_HAS_TOOLS+x}" ] && [ -f "$config" ]; then
      _has_custom_tools_filter=$(jq -r 'if (.evaluators.input_pii | has("tools")) and (.evaluators.input_pii.tools | length > 0) then "yes" else "" end' "$config" 2>/dev/null) || _has_custom_tools_filter=""
    fi

    if [ -z "$_has_custom_tools_filter" ]; then
      case "$tool_name" in
        Write|Edit|Bash) ;;
        *)
          INPUT_PII_REASON="Tool '$tool_name' not in input PII scan list"
          return 0
          ;;
      esac
    else
      # Custom tools filter — check pre-extracted list first, jq only as last resort
      if [ -n "${_CFG_INPUT_PII_TOOLS+x}" ]; then
        # Pre-extracted comma-separated tools list
        if [ -n "$_CFG_INPUT_PII_TOOLS" ]; then
          case ",$_CFG_INPUT_PII_TOOLS," in
            *",$tool_name,"*) ;;
            *)
              INPUT_PII_REASON="Tool '$tool_name' not in input PII scan list"
              return 0
              ;;
          esac
        fi
        # Empty list → scan all tools (fall through)
      else
        # Fallback: jq (standalone testing / no handler pre-extraction)
        local tool_match
        tool_match=$(jq -r --arg t "$tool_name" '.evaluators.input_pii.tools // [] | map(select(. == $t)) | length' "$config" 2>/dev/null) || tool_match=0
        if [ "$tool_match" -eq 0 ]; then
          local tools_len
          tools_len=$(jq -r '.evaluators.input_pii.tools // [] | length' "$config" 2>/dev/null) || tools_len=0
          if [ "$tools_len" != "0" ]; then
            INPUT_PII_REASON="Tool '$tool_name' not in input PII scan list"
            return 0
          fi
        fi
      fi
    fi
  else
    # Fallback: read from config file (standalone testing / no handler)
    if [ ! -f "$config" ]; then
      return 0
    fi

    local _ip
    _ip=$(jq -c '.evaluators.input_pii // {}' "$config" 2>/dev/null) || return 0

    if [ "$(printf '%s' "$_ip" | jq -r 'if .enabled == false then "false" else "true" end')" = "false" ]; then
      INPUT_PII_REASON="InputPII evaluator disabled"
      return 0
    fi

    # Tools filter
    local tools_filter
    tools_filter=$(printf '%s' "$_ip" | jq -r 'if has("tools") then (.tools // [] | length | tostring) else "default" end') || tools_filter="default"
    if [ "$tools_filter" = "default" ]; then
      case "$tool_name" in
        Write|Edit|Bash) ;;
        *)
          INPUT_PII_REASON="Tool '$tool_name' not in input PII scan list"
          return 0
          ;;
      esac
    elif [ "$tools_filter" != "0" ]; then
      local tool_match
      tool_match=$(printf '%s' "$_ip" | jq -r --arg t "$tool_name" '.tools // [] | map(select(. == $t)) | length') || tool_match=0
      if [ "$tool_match" -eq 0 ]; then
        INPUT_PII_REASON="Tool '$tool_name' not in input PII scan list"
        return 0
      fi
    fi

    on_detect=$(printf '%s' "$_ip" | jq -r '.on_detect // "ask"') || on_detect="ask"

    # Resolve PII patterns with fallback
    local pii_patterns_nl
    pii_patterns_nl=$(printf '%s' "$_ip" | jq -r '.pii_patterns[]? // empty')
    if [ -z "$pii_patterns_nl" ]; then
      pii_patterns_nl=$(jq -r '.evaluators.result_transform.pii_patterns[]? // empty' "$config" 2>/dev/null) || pii_patterns_nl=""
    fi
    # Convert newline-separated to RS-delimited for consistent handling
    pii_patterns_raw=$(printf '%s' "$pii_patterns_nl" | tr '\n' '\036')

    # Resolve PII allowlist
    local pii_allowlist_nl
    pii_allowlist_nl=$(printf '%s' "$_ip" | jq -r '.pii_allowlist[]? // empty')
    pii_allowlist_raw=$(printf '%s' "$pii_allowlist_nl" | tr '\n' '\036')

    # Resolve compliance
    local cat_comp
    cat_comp=$(printf '%s' "$_ip" | jq -c '.compliance_by_category.pii // []') || cat_comp="[]"
    if [ "$cat_comp" = "[]" ] || [ "$cat_comp" = "null" ]; then
      cat_comp=$(jq -c '.evaluators.result_transform.compliance_by_category.pii // []' "$config" 2>/dev/null) || cat_comp="[]"
    fi
    all_compliance="$cat_comp"
  fi

  if [ -z "$pii_patterns_raw" ]; then
    INPUT_PII_REASON="No PII patterns configured"
    return 0
  fi

  # Extract scannable text from tool_input JSON
  # Write uses .content, Edit uses .new_string, Bash uses .command
  local scan_text
  scan_text=$(printf '%s' "$tool_input" | jq -r '.content // .new_string // .command // tostring' 2>/dev/null) || scan_text="$tool_input"

  # Scan for PII patterns
  local detections="[]"
  local found_any=false
  local _pii_pats
  IFS=$'\x1e' read -ra _pii_pats <<< "$pii_patterns_raw"

  # Parse allowlist patterns
  local _allow_pats=()
  if [ -n "${pii_allowlist_raw:-}" ]; then
    IFS=$'\x1e' read -ra _allow_pats <<< "$pii_allowlist_raw"
  fi

  for pattern in "${_pii_pats[@]}"; do
    [ -z "$pattern" ] && continue
    if printf '%s' "$scan_text" | grep -qE -- "$pattern"; then
      # PII pattern matched — check allowlist line-by-line
      if [ "${#_allow_pats[@]}" -gt 0 ]; then
        local _has_non_allowed=false
        while IFS= read -r _line; do
          if printf '%s' "$_line" | grep -qE -- "$pattern"; then
            local _allowed=false
            for _ap in "${_allow_pats[@]}"; do
              [ -z "$_ap" ] && continue
              if printf '%s' "$_line" | grep -qE -- "$_ap"; then
                _allowed=true
                break
              fi
            done
            if [ "$_allowed" = false ]; then
              _has_non_allowed=true
              break
            fi
          fi
        done <<< "$scan_text"
        if [ "$_has_non_allowed" = false ]; then
          continue  # All matching lines were allowlisted
        fi
      fi
      found_any=true
      detections=$(printf '%s' "$detections" | jq -c --arg p "$pattern" '. + [{"category":"pii","pattern":$p}]')
    fi
  done

  INPUT_PII_DETECTIONS="$detections"
  INPUT_PII_COMPLIANCE="$all_compliance"

  if [ "$found_any" = false ]; then
    return 0
  fi

  local detection_summary
  detection_summary=$(printf '%s' "$detections" | jq -r '[.[] | "\(.category): \(.pattern)"] | join(", ")')

  INPUT_PII_DECISION="$on_detect"

  case "$on_detect" in
    warn)
      INPUT_PII_REASON="[LaneKeep] WARNING from InputPII (Tier 4)\nPII detected in tool input: ${detection_summary}"
      return 0
      ;;
    deny)
      INPUT_PII_PASSED=false
      INPUT_PII_REASON="[LaneKeep] DENIED by InputPII (Tier 4)\nPII detected in tool input: ${detection_summary}\nSuggestion: Remove PII from tool input before proceeding"
      return 1
      ;;
    ask|*)
      INPUT_PII_PASSED=false
      INPUT_PII_DECISION="ask"
      INPUT_PII_REASON="[LaneKeep] NEEDS APPROVAL — InputPII (Tier 4)\nPII detected in tool input: ${detection_summary}\nThis operation contains PII and requires user confirmation"
      return 1
      ;;
  esac
}
