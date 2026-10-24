#!/usr/bin/env bats
# Command-classification regression corpus — imported from planlock's read-only
# Bash classifier (82 fixtures + 29 bypass strings + 4 controls, see
# tests/fixtures/command-classification/README.md).
#
# `expect` is LaneKeep's verdict (allow/ask/deny) from hardblock + rules, NOT
# planlock's read-only verdict (kept under `.planlock` for provenance).
# `known_gap: true` rows are dangerous commands LaneKeep currently allows; the
# gap test fails once a rule closes one, so the fixture gets flipped.

load ../test_helper

FIXTURES="$BATS_TEST_DIRNAME/../fixtures/command-classification"

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"
  export LANEKEEP_TASKSPEC_FILE=""
  export LANEKEEP_STATE_FILE="$TEST_TMP/state.json"
  export LANEKEEP_TRACE_FILE="$TEST_TMP/.lanekeep/traces/test-session.jsonl"
  export LANEKEEP_SESSION_ID="test-session"
  export PROJECT_DIR="$TEST_TMP"
  mkdir -p "$TEST_TMP/.lanekeep/traces"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$LANEKEEP_CONFIG_FILE"
  printf '{"action_count":0,"input_token_count":0,"output_token_count":0,"start_epoch":%s}\n' "$(date +%s)" > "$LANEKEEP_STATE_FILE"
  source "$LANEKEEP_DIR/lib/eval-hardblock.sh"
  source "$LANEKEEP_DIR/lib/eval-rules.sh"
}
teardown() { rm -rf "$TEST_TMP"; return 0; }

# Print LaneKeep's verdict for a Bash command: allow | ask | deny
_classify() {
  local input
  input=$(jq -cn --arg c "$1" '{command:$c}')
  if ! hardblock_check "Bash" "$input" >/dev/null 2>&1; then
    echo deny
    return
  fi
  rules_eval "Bash" "$input" >/dev/null 2>&1 || true
  if [ "$RULES_PASSED" = "false" ]; then echo "${RULES_DECISION:-deny}"; else echo allow; fi
}

# Check every row of a fixture file; known_gap rows must still be open
# (verdict != expect). Prints all mismatches before failing.
_check_corpus() {
  local file="$1" fails=0 row id cmd expect gap got
  while IFS= read -r row; do
    id=$(jq -r .id <<<"$row")
    cmd=$(jq -r .cmd <<<"$row")
    expect=$(jq -r .expect <<<"$row")
    gap=$(jq -r .known_gap <<<"$row")
    got=$(_classify "$cmd")
    if [ "$gap" = "true" ]; then
      if [ "$got" = "$expect" ]; then
        echo "GAP CLOSED $id: now '$got' — set known_gap=false in $(basename "$file"): $cmd"
        fails=$((fails + 1))
      fi
    elif [ "$got" != "$expect" ]; then
      echo "MISMATCH $id: expected '$expect', got '$got': $cmd"
      fails=$((fails + 1))
    fi
  done < "$file"
  [ "$fails" -eq 0 ]
}

# ── Corpus shape ──

@test "corpus: 82 command fixtures, 29 bypass strings, 4 controls" {
  [ "$(wc -l < "$FIXTURES/commands.jsonl")" -eq 82 ]
  [ "$(wc -l < "$FIXTURES/bypass.jsonl")" -eq 29 ]
  [ "$(wc -l < "$FIXTURES/controls.jsonl")" -eq 4 ]
}

@test "corpus: every row has a valid expect and known_gap" {
  run jq -s -e 'all(.[]; (.expect | IN("allow","ask","deny")) and (.known_gap | type == "boolean") and (.cmd | type == "string"))' \
    "$FIXTURES"/commands.jsonl "$FIXTURES"/bypass.jsonl "$FIXTURES"/controls.jsonl
  [ "$status" -eq 0 ]
}

@test "corpus: every known_gap row targets deny and gives a reason" {
  run jq -s -e 'all(.[] | select(.known_gap); .expect == "deny" and (.gap_reason | length > 0))' \
    "$FIXTURES"/commands.jsonl "$FIXTURES"/bypass.jsonl "$FIXTURES"/controls.jsonl
  [ "$status" -eq 0 ]
}

# ── Verdicts ──

@test "classification: planlock command fixtures match LaneKeep verdicts" {
  run _check_corpus "$FIXTURES/commands.jsonl"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "classification: planlock bypass strings match LaneKeep verdicts" {
  run _check_corpus "$FIXTURES/bypass.jsonl"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "classification: planlock false-positive controls stay allowed" {
  run _check_corpus "$FIXTURES/controls.jsonl"
  echo "$output"
  [ "$status" -eq 0 ]
}
