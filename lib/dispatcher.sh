#!/usr/bin/env bash
# Aggregate evaluator results into allow/deny + formatted feedback

format_denial() {
  local primary_reason="$1"
  shift
  local results=("$@")

  # Primary reason is already formatted by the failing evaluator
  # Append summary of all evaluator results
  local summary="$primary_reason"
  summary="${summary}"$'\n\n'"--- Evaluation Summary ---"

  for r in "${results[@]}"; do
    # Extract all fields in a single jq call (4→1 subprocess per result)
    local name tier passed detail
    eval "$(printf '%s' "$r" | jq -r '
      "name=" + (.name | @sh),
      "tier=" + (.tier | tostring | @sh),
      "passed=" + (.passed | tostring | @sh),
      "detail=" + (.detail | @sh)' 2>/dev/null)"
    if [ "$passed" = "true" ]; then
      summary="${summary}"$'\n'"  [PASS] ${name} (Tier ${tier})"
    else
      summary="${summary}"$'\n'"  [FAIL] ${name} (Tier ${tier}): ${detail}"
    fi
  done

  printf '%s' "$summary"
}
