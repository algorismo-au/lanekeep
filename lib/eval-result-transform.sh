#!/usr/bin/env bash
# Tier 5: ResultTransform evaluator — scans tool output for injection and secrets
#
# Patterns support two formats:
#   String:  "AKIA[0-9A-Z]{16}"                          (uses global on_detect)
#   Object:  {"pattern":"...", "decision":"block",        (per-pattern override)
#             "reason":"Private key leak",
#             "compliance":["PCI-DSS 3.5.1"]}
#
# policy_scan reuses policy denied lists for output-side scanning:
#   "policy_scan": {"enabled": true, "categories": ["domains", "ips"]}

RESULT_TRANSFORM_PASSED=true
RESULT_TRANSFORM_REASON=""
RESULT_TRANSFORM_ACTION="pass"       # "pass" | "redact" | "warn" | "block"
RESULT_TRANSFORM_CONTENT=""          # transformed content (empty = unchanged)
RESULT_TRANSFORM_DETECTIONS="[]"     # JSON array of what was found
RESULT_TRANSFORM_COMPLIANCE="[]"     # JSON array of compliance references

# Decision severity: block(3) > redact(2) > warn(1) > pass(0)
_rt_severity() {
  case "$1" in
    block) echo 3 ;; redact) echo 2 ;; warn) echo 1 ;; *) echo 0 ;;
  esac
}

# _rt_scan_patterns <category> <grep_flags> <jq_key>
# Scans $transformed against patterns from $_rt[$jq_key].
# Patterns can be strings or enriched {pattern, decision, reason, compliance} objects.
# Updates caller's: detections, found_any, _rt_max_decision
_rt_scan_patterns() {
  local category="$1" grep_flags="$2" jq_key="$3"

  # Normalize patterns to JSONL: one {p, d, r, c} object per line
  # Using JSONL instead of @tsv to preserve backslashes in regex patterns
  local entries
  entries=$(printf '%s' "$_rt" | jq -c --arg k "$jq_key" '
    .[$k] // [] | .[] |
    if type == "string" then {p: .}
    else {p: (.pattern // ""), d: (.decision // null), r: (.reason // null), c: (.compliance // null)}
    end') || return 0
  [ -z "$entries" ] && return 0

  while IFS= read -r _entry; do
    [ -z "$_entry" ] && continue
    local pattern
    pattern=$(printf '%s' "$_entry" | jq -r '.p')
    [ -z "$pattern" ] && continue

    local matched=false
    if [[ "$grep_flags" == *P* ]]; then
      if timeout 1 grep -q${grep_flags} -- "$pattern" <<< "$transformed" 2>/dev/null; then
        matched=true
      fi
    else
      if grep -q${grep_flags} -- "$pattern" <<< "$transformed"; then
        matched=true
      fi
    fi

    if [ "$matched" = true ]; then
      found_any=true
      # Build detection with optional enriched fields (null = omitted from output)
      detections=$(printf '%s' "$detections" | jq -c --argjson e "$_entry" --arg c "$category" '
        . + [{ category: $c, pattern: $e.p }
          + (if $e.d then {decision: $e.d} else {} end)
          + (if $e.r then {reason: $e.r} else {} end)
          + (if $e.c then {compliance: $e.c} else {} end)]')

      # Track most severe per-pattern decision
      local p_decision
      p_decision=$(printf '%s' "$_entry" | jq -r '.d // empty')
      if [ -n "$p_decision" ]; then
        local sev=$(_rt_severity "$p_decision")
        local cur=$(_rt_severity "$_rt_max_decision")
        if [ "$sev" -gt "$cur" ]; then
          _rt_max_decision="$p_decision"
        fi
      fi
    fi
  done <<< "$entries"
}

# _rt_extract_patterns <jq_key>
# Extracts raw pattern strings (from both string and object formats) for redaction
_rt_extract_patterns() {
  printf '%s' "$_rt" | jq -r --arg k "$1" '
    .[$k] // [] | .[] |
    if type == "string" then . else (.pattern // empty) end'
}

result_transform_eval() {
  local tool_name="$1"
  local tool_result_text="$2"
  RESULT_TRANSFORM_PASSED=true
  RESULT_TRANSFORM_REASON="Passed"
  RESULT_TRANSFORM_ACTION="pass"
  RESULT_TRANSFORM_CONTENT=""
  RESULT_TRANSFORM_DETECTIONS="[]"
  RESULT_TRANSFORM_COMPLIANCE="[]"

  local config="$LANEKEEP_CONFIG_FILE"
  if [ ! -f "$config" ]; then
    return 0
  fi

  # Extract result_transform section once (57KB config → ~2KB section)
  local _rt
  _rt=$(jq -c '.evaluators.result_transform // {}' "$config" 2>/dev/null) || return 0

  # Supplement pattern arrays from defaults (ensures new default patterns reach all projects)
  if [ -n "${LANEKEEP_DIR:-}" ]; then
    local _rt_def_file="$LANEKEEP_DIR/defaults/lanekeep.json"
    if [ -f "$_rt_def_file" ] && [ "$config" != "$_rt_def_file" ]; then
      _rt=$(jq -c --slurpfile def "$_rt_def_file" '
        ($def[0].evaluators.result_transform // {}) as $drt |
        def supplement($key):
          (.[$key] // []) as $have |
          ($have | map(if type == "string" then . else (.pattern // "") end)) as $have_strs |
          $have + [($drt[$key] // [])[] |
            (if type == "string" then . else (.pattern // "") end) as $p |
            select(($have_strs | index($p)) == null)
          ];
        supplement("secret_patterns") as $sp |
        supplement("injection_patterns") as $ip |
        supplement("hidden_char_patterns") as $hp |
        supplement("css_hiding_patterns") as $cp |
        supplement("html_comment_injection_patterns") as $hcip |
        . + {
          secret_patterns: $sp, injection_patterns: $ip,
          hidden_char_patterns: $hp, css_hiding_patterns: $cp,
          html_comment_injection_patterns: $hcip
        }
      ' <<< "$_rt") || true
    fi
  fi

  # Check if evaluator is enabled
  if [ "$(printf '%s' "$_rt" | jq -r 'if .enabled == false then "false" else "true" end')" = "false" ]; then
    RESULT_TRANSFORM_REASON="ResultTransform evaluator disabled"
    return 0
  fi

  # Check tool filter — empty means all tools
  local tools_filter
  tools_filter=$(printf '%s' "$_rt" | jq -r '.tools // [] | length') || tools_filter=0
  if [ "$tools_filter" -gt 0 ]; then
    local tool_match
    tool_match=$(printf '%s' "$_rt" | jq -r --arg t "$tool_name" '.tools // [] | map(select(. == $t)) | length') || tool_match=0
    if [ "$tool_match" -eq 0 ]; then
      RESULT_TRANSFORM_REASON="Tool '$tool_name' not in scan list"
      return 0
    fi
  fi

  # --- Size checks (early, before pattern scanning) ---
  local max_result_bytes truncate_at
  max_result_bytes=$(printf '%s' "$_rt" | jq -r '.max_result_bytes // 1048576') || max_result_bytes=1048576
  truncate_at=$(printf '%s' "$_rt" | jq -r '.truncate_at // 524288') || truncate_at=524288

  local result_size=${#tool_result_text}

  if [ "$result_size" -gt "$max_result_bytes" ]; then
    RESULT_TRANSFORM_PASSED=false
    RESULT_TRANSFORM_ACTION="block"
    RESULT_TRANSFORM_REASON="[LaneKeep] BLOCKED by ResultTransform (Tier 5)\nResult size ${result_size} bytes exceeds max_result_bytes (${max_result_bytes})"
    RESULT_TRANSFORM_DETECTIONS=$(jq -n '[{"category":"size","detail":"exceeds max_result_bytes"}]')
    return 1
  fi

  local transformed="$tool_result_text"
  if [ "$result_size" -gt "$truncate_at" ]; then
    transformed="${tool_result_text:0:$truncate_at}... [TRUNCATED by LaneKeep: ${result_size} bytes exceeded ${truncate_at} byte limit]"
  fi

  # --- Pattern scanning ---
  local on_detect
  on_detect=$(printf '%s' "$_rt" | jq -r '.on_detect // "redact"') || on_detect="redact"

  local detections="[]"
  local found_any=false
  local _rt_max_decision=""

  # Scan all pattern categories (supports both string and enriched object patterns)
  _rt_scan_patterns "injection"      "iF"  "injection_patterns"
  _rt_scan_patterns "secret"         "iE"  "secret_patterns"
  _rt_scan_patterns "hidden_char"    "P"   "hidden_char_patterns"
  _rt_scan_patterns "css_hiding"     "iP"  "css_hiding_patterns"
  _rt_scan_patterns "html_injection" "iP"  "html_comment_injection_patterns"

  # --- Policy scan: reuse policy denied lists for output-side scanning ---
  local _ps_enabled
  _ps_enabled=$(printf '%s' "$_rt" | jq -r '.policy_scan.enabled // false') || _ps_enabled=false
  if [ "$_ps_enabled" = "true" ]; then
    local _ps_cats
    _ps_cats=$(printf '%s' "$_rt" | jq -r '.policy_scan.categories // [] | .[]') || _ps_cats=""
    while IFS= read -r _ps_cat; do
      [ -z "$_ps_cat" ] && continue
      local _ps_denied
      _ps_denied=$(jq -r --arg c "$_ps_cat" '.policies[$c].denied // [] | .[]' "$config" 2>/dev/null) || continue
      while IFS= read -r _ps_pattern; do
        [ -z "$_ps_pattern" ] && continue
        if grep -qiE -- "$_ps_pattern" <<< "$transformed" 2>/dev/null; then
          found_any=true
          detections=$(printf '%s' "$detections" | jq -c \
            --arg c "policy:$_ps_cat" --arg p "$_ps_pattern" \
            '. + [{category:$c, pattern:$p}]')
        fi
      done <<< "$_ps_denied"
    done <<< "$_ps_cats"
  fi

  RESULT_TRANSFORM_DETECTIONS="$detections"

  # Resolve compliance: merge per-pattern compliance + category-level compliance
  if [ "$found_any" = true ]; then
    local all_compliance="[]"
    # Per-pattern compliance from enriched patterns
    local per_pat_comp
    per_pat_comp=$(printf '%s' "$detections" | jq -c '[.[] | .compliance // [] | .[]] | unique') || per_pat_comp="[]"
    all_compliance=$(printf '%s\n%s' "$all_compliance" "$per_pat_comp" | jq -sc 'add | unique')
    # Category-level compliance from compliance_by_category
    local categories
    categories=$(printf '%s' "$detections" | jq -r '[.[].category] | unique | .[]')
    while IFS= read -r cat; do
      [ -z "$cat" ] && continue
      local cat_comp
      cat_comp=$(printf '%s' "$_rt" | jq -c --arg c "$cat" '.compliance_by_category[$c] // []') || cat_comp="[]"
      all_compliance=$(printf '%s\n%s' "$all_compliance" "$cat_comp" | jq -sc 'add | unique')
    done <<< "$categories"
    RESULT_TRANSFORM_COMPLIANCE="$all_compliance"
  fi

  if [ "$found_any" = false ]; then
    # If we truncated, still report that
    if [ "$result_size" -gt "$truncate_at" ]; then
      RESULT_TRANSFORM_ACTION="redact"
      RESULT_TRANSFORM_CONTENT="$transformed"
      RESULT_TRANSFORM_REASON="[LaneKeep] Result truncated (${result_size} > ${truncate_at} bytes)"
    fi
    return 0
  fi

  # --- Resolve effective action ---
  # Per-pattern decisions can only escalate, never de-escalate
  local effective_action="$on_detect"
  if [ -n "$_rt_max_decision" ]; then
    local on_sev=$(_rt_severity "$on_detect")
    local max_sev=$(_rt_severity "$_rt_max_decision")
    if [ "$max_sev" -gt "$on_sev" ]; then
      effective_action="$_rt_max_decision"
    fi
  fi

  # Build summary — use per-pattern reason when available, else pattern
  local detection_summary
  detection_summary=$(printf '%s' "$detections" | jq -r '
    [.[] | if .reason then "\(.category): \(.reason)" else "\(.category): \(.pattern)" end] | join(", ")')

  case "$effective_action" in
    block)
      RESULT_TRANSFORM_PASSED=false
      RESULT_TRANSFORM_ACTION="block"
      RESULT_TRANSFORM_REASON="[LaneKeep] BLOCKED by ResultTransform (Tier 5)\nDetected: ${detection_summary}"
      return 1
      ;;
    warn)
      RESULT_TRANSFORM_ACTION="warn"
      RESULT_TRANSFORM_REASON="[LaneKeep] WARNING from ResultTransform (Tier 5)\nDetected: ${detection_summary}"
      return 0
      ;;
    redact|*)
      RESULT_TRANSFORM_ACTION="redact"

      # Redact injection patterns (case-insensitive fixed string via awk)
      local injection_patterns
      injection_patterns=$(_rt_extract_patterns "injection_patterns")
      while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        # VULN-11: Use ENVIRON[] instead of awk -v to prevent escape injection
        transformed=$(printf '%s' "$transformed" | LANEKEEP_PAT="$pattern" LANEKEEP_REP="[REDACTED:injection]" awk '
          BEGIN { IGNORECASE=1; pat=ENVIRON["LANEKEEP_PAT"]; rep=ENVIRON["LANEKEEP_REP"] }
          { gsub(pat, rep); print }')
      done <<< "$injection_patterns"

      # Redact secret patterns (case-insensitive regex via awk)
      local secret_patterns
      secret_patterns=$(_rt_extract_patterns "secret_patterns")
      while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        transformed=$(printf '%s' "$transformed" | LANEKEEP_PAT="$pattern" LANEKEEP_REP="[REDACTED:secret]" awk '
          BEGIN { IGNORECASE=1; pat=ENVIRON["LANEKEEP_PAT"]; rep=ENVIRON["LANEKEEP_REP"] }
          { gsub(pat, rep); print }')
      done <<< "$secret_patterns"

      # Redact policy scan matches (case-insensitive regex via awk)
      if [ "$_ps_enabled" = "true" ]; then
        local _ps_cats_r
        _ps_cats_r=$(printf '%s' "$_rt" | jq -r '.policy_scan.categories // [] | .[]') || _ps_cats_r=""
        while IFS= read -r _ps_cat; do
          [ -z "$_ps_cat" ] && continue
          local _ps_denied_r
          _ps_denied_r=$(jq -r --arg c "$_ps_cat" '.policies[$c].denied // [] | .[]' "$config" 2>/dev/null) || continue
          while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            transformed=$(printf '%s' "$transformed" | LANEKEEP_PAT="$pattern" LANEKEEP_REP="[REDACTED:policy:${_ps_cat}]" awk '
              BEGIN { IGNORECASE=1; pat=ENVIRON["LANEKEEP_PAT"]; rep=ENVIRON["LANEKEEP_REP"] }
              { gsub(pat, rep); print }')
          done <<< "$_ps_denied_r"
        done <<< "$_ps_cats_r"
      fi

      RESULT_TRANSFORM_CONTENT="$transformed"
      RESULT_TRANSFORM_REASON="[LaneKeep] REDACTED by ResultTransform (Tier 5)\nDetected: ${detection_summary}"
      return 0
      ;;
  esac
}
