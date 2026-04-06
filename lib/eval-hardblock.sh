#!/usr/bin/env bash
# shellcheck disable=SC2034  # HARDBLOCK_REASON set here, read externally via indirection
# Hard-block: fast substring match before evaluation pipeline

HARDBLOCK_REASON=""
HARDBLOCK_WARNED=""

# Cache uconv availability at module load time
_LANEKEEP_HAS_UCONV=""
if command -v uconv >/dev/null 2>&1; then _LANEKEEP_HAS_UCONV=1; else _LANEKEEP_HAS_UCONV=0; fi

hardblock_check() {
  local tool_name="$1"
  local tool_input="$2"
  HARDBLOCK_REASON=""
  HARDBLOCK_WARNED=""
  local _hb_overridden=""

  local search_text
  # Strip null bytes, zero-width chars (U+200B-U+200F, U+FEFF, U+2060, U+00AD),
  # strip quotes (single/double), optionally NFKC-normalize,
  # and normalize Unicode fullwidth chars (U+FF01..U+FF5E → ASCII)
  search_text=$(printf '%s %s' "$tool_name" "$tool_input" \
    | tr -d '\000' \
    | LC_ALL=C sed \
        -e 's/\xe2\x80[\x8b-\x8f]//g' \
        -e 's/\xe2\x81\xa0//g' \
        -e 's/\xef\xbb\xbf//g' \
        -e 's/\xc2\xad//g' \
        -e 's/\xef\xbc[\x81-\xbe]/\x21/g; s/\xef\xbd[\x80-\x9e]/\x60/g' \
        -e "s/'//g; s/\"//g" \
    | { uconv -x "NFKC" 2>/dev/null || cat; } \
    | tr '[:upper:]' '[:lower:]')

  # Resolve hard_blocks: use pre-extracted var or fall back to jq
  local _hb_source _hbr_source
  if [ -n "${_CFG_HARD_BLOCKS+x}" ] && [ -n "$_CFG_HARD_BLOCKS" ]; then
    _hb_source="$_CFG_HARD_BLOCKS"
  elif [ -f "$LANEKEEP_CONFIG_FILE" ]; then
    _hb_source=$(jq -r '.hard_blocks[]? // empty' "$LANEKEEP_CONFIG_FILE") || _hb_source=""
  else
    return 0
  fi

  if [ -n "${_CFG_HARD_BLOCKS_REGEX+x}" ] && [ -n "$_CFG_HARD_BLOCKS_REGEX" ]; then
    _hbr_source="$_CFG_HARD_BLOCKS_REGEX"
  elif [ -f "$LANEKEEP_CONFIG_FILE" ]; then
    _hbr_source=$(jq -r '.hard_blocks_regex[]? // empty' "$LANEKEEP_CONFIG_FILE") || _hbr_source=""
  else
    _hbr_source=""
  fi

  # Resolve hard_block_overrides: pattern=decision (newline-delimited)
  local _hbo_source=""
  if [ -n "${_CFG_HARD_BLOCK_OVERRIDES+x}" ] && [ -n "$_CFG_HARD_BLOCK_OVERRIDES" ]; then
    _hbo_source="$_CFG_HARD_BLOCK_OVERRIDES"
  elif [ -f "$LANEKEEP_CONFIG_FILE" ]; then
    _hbo_source=$(jq -r '.hard_block_overrides // {} | to_entries[] | "\(.key)=\(.value)"' "$LANEKEEP_CONFIG_FILE" 2>/dev/null) || _hbo_source=""
  fi

  # Fixed-string patterns: lowercase all at once, single grep across all patterns
  if [ -n "$_hb_source" ]; then
    local _hb_lower _matched
    _hb_lower=$(printf '%s\n' "$_hb_source" | tr '[:upper:]' '[:lower:]')
    _matched=$(printf '%s' "$search_text" | grep -oFm1 -f <(printf '%s\n' "$_hb_lower") 2>/dev/null) || true
    if [ -n "$_matched" ]; then
      local _override_decision=""
      _override_decision=$(_hardblock_lookup_override "$_matched" "$_hbo_source")
      if [ "$_override_decision" = "disable" ]; then
        _hb_overridden=1
      elif [ "$_override_decision" = "warn" ]; then
        _hb_overridden=1
        HARDBLOCK_WARNED="[LaneKeep] WARN (Tier 1 — overridden)\nPattern matched: '$_matched'\nAction: $tool_name"
        echo -e "$HARDBLOCK_WARNED" >&2
      else
        HARDBLOCK_REASON="[LaneKeep] HARD-BLOCKED (Tier 1)\nPattern matched: '$_matched'\nAction: $tool_name"
        return 1
      fi
    fi
  fi

  # Regex patterns: skip if fixed-string was already overridden (warn/disable)
  if [ -n "$_hb_overridden" ]; then
    return 0
  fi

  # Regex patterns: validate with bash built-in (no subprocess), combine into single grep
  if [ -n "$_hbr_source" ]; then
    local safe_patterns=() pattern
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      # Skip patterns with nested quantifiers (ReDoS risk) — bash ERE match, no subprocess
      if [[ "$pattern" =~ \([^\)]*[+*]\)[+*?] ]]; then
        echo "[LaneKeep] WARN: skipping hard_blocks_regex with ReDoS risk: $pattern" >&2
        continue
      fi
      safe_patterns+=("$pattern")
    done <<< "$_hbr_source"

    if [ ${#safe_patterns[@]} -gt 0 ]; then
      local combined
      combined=$(printf '(?:%s)' "${safe_patterns[0]}")
      local p; for p in "${safe_patterns[@]:1}"; do combined+="|(?:$p)"; done
      if printf '%s' "$search_text" | timeout 1 grep -qP "$combined" 2>/dev/null; then
        HARDBLOCK_REASON="[LaneKeep] HARD-BLOCKED (Tier 1)\nRegex matched destructive pattern\nAction: $tool_name"
        return 1
      fi
    fi
  fi

  return 0
}

# Lookup override decision for a matched pattern
# Args: $1=matched_pattern (lowercase), $2=overrides_source (newline-delimited "pattern=decision")
# Returns: prints "warn", "disable", or "" (no override)
_hardblock_lookup_override() {
  local matched="$1" overrides="$2"
  [ -z "$overrides" ] && return 0
  local line key val
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key="${line%=*}"
    val="${line##*=}"
    # Case-insensitive compare
    key=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
    if [ "$key" = "$matched" ]; then
      printf '%s' "$val"
      return 0
    fi
  done <<< "$overrides"
  return 0
}
