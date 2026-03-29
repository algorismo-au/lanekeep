#!/usr/bin/env bash
# shellcheck disable=SC2034  # HARDBLOCK_REASON set here, read externally via indirection
# Hard-block: fast substring match before evaluation pipeline

HARDBLOCK_REASON=""

# Cache uconv availability at module load time
_LANEKEEP_HAS_UCONV=""
if command -v uconv >/dev/null 2>&1; then _LANEKEEP_HAS_UCONV=1; else _LANEKEEP_HAS_UCONV=0; fi

hardblock_check() {
  local tool_name="$1"
  local tool_input="$2"
  HARDBLOCK_REASON=""

  local search_text
  # Strip null bytes, zero-width chars (U+200B-U+200F, U+FEFF, U+2060, U+00AD),
  # strip quotes (single/double), optionally NFC-normalize,
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
    | { if [ "$_LANEKEEP_HAS_UCONV" = "1" ]; then uconv -x "NFC" 2>/dev/null; else cat; fi; } \
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

  # Fixed-string patterns: lowercase all at once, single grep across all patterns
  if [ -n "$_hb_source" ]; then
    local _hb_lower _matched
    _hb_lower=$(printf '%s\n' "$_hb_source" | tr '[:upper:]' '[:lower:]')
    _matched=$(printf '%s' "$search_text" | grep -oFm1 -f <(printf '%s\n' "$_hb_lower") 2>/dev/null) || true
    if [ -n "$_matched" ]; then
      HARDBLOCK_REASON="[LaneKeep] HARD-BLOCKED (Tier 1)\nPattern matched: '$_matched'\nAction: $tool_name"
      return 1
    fi
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
