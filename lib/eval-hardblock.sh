#!/usr/bin/env bash
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
    | { [ "$_LANEKEEP_HAS_UCONV" = "1" ] && uconv -x "NFC" 2>/dev/null || cat; } \
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

  local pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    local lower_pattern
    lower_pattern=$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$search_text" | grep -qF "$lower_pattern"; then
      HARDBLOCK_REASON="[LaneKeep] HARD-BLOCKED (Tier 1)\nPattern matched: '$pattern'\nAction: $tool_name"
      return 1
    fi
  done <<< "$_hb_source"

  # Regex patterns for flag-reordering-aware matching
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    # Skip patterns with nested quantifiers (ReDoS risk)
    if printf '%s' "$pattern" | grep -qE '\([^)]*[+*]\)[+*?]'; then
      echo "[LaneKeep] WARN: skipping hard_blocks_regex with ReDoS risk: $pattern" >&2
      continue
    fi
    if printf '%s' "$search_text" | timeout 1 grep -qP "$pattern" 2>/dev/null; then
      HARDBLOCK_REASON="[LaneKeep] HARD-BLOCKED (Tier 1)\nRegex matched destructive pattern\nAction: $tool_name"
      return 1
    fi
  done <<< "$_hbr_source"

  return 0
}
