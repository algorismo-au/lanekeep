#!/usr/bin/env bash
# Generate a comprehensive lanekeep.json with shipped default rules.
# Merges defaults + pattern rules + policies into one file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANEKEEP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULTS="$LANEKEEP_DIR/defaults/lanekeep.json"
PATTERNS="$LANEKEEP_DIR/defaults/lanekeep-pattern-rules.json"
POLICIES="$LANEKEEP_DIR/defaults/lanekeep-policies.json"

OUTPUT="${1:-./lanekeep.json}"

for f in "$DEFAULTS" "$PATTERNS" "$POLICIES"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: missing $f" >&2
    exit 1
  fi
done

jq --slurpfile pat "$PATTERNS" --slurpfile pol "$POLICIES" '
  .rules += ($pat[0].rules // []) |
  .policies = ($pol[0].policies // {})
' "$DEFAULTS" > "$OUTPUT"

RULE_COUNT=$(jq '.rules | length' "$OUTPUT")
POLICY_COUNT=$(jq '[.policies // {} | to_entries[] | .value |
  if type == "object" then ((.allowed // [] | length) + (.denied // [] | length))
  elif type == "array" then length else 0 end
] | add // 0' "$OUTPUT")

echo "Created $OUTPUT"
echo "  Rules: $RULE_COUNT"
echo "  Policy entries: $POLICY_COUNT"
