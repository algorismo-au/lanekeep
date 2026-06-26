#!/usr/bin/env bats
# Tests for lanekeep-parse-plan — scaffold03 IMPLEMENTATION_PLAN.json → TaskSpec

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  PLAN="$TEST_TMP/plan.json"
  BIN="$LANEKEEP_DIR/bin/lanekeep-parse-plan"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

write_plan() {
  cat > "$PLAN" <<'EOF'
{
  "schema_version": "1.0",
  "project": "test",
  "defaults": {
    "budget": { "max_actions": 200, "timeout_seconds": 1800 },
    "tools_needed": ["Read", "Edit"]
  },
  "now": [
    {
      "id": "T-42",
      "title": "Wire headless sink",
      "goal": "Implement the bundle reader",
      "tools_needed": ["Read", "Edit", "Bash"],
      "denied_tools": ["WebFetch"],
      "budget": { "max_actions": 150, "timeout_seconds": 1200 }
    },
    { "id": "T-43", "title": "Followup" }
  ],
  "next": [{ "id": "T-44", "title": "Queued" }],
  "blocked": [{ "id": "T-19", "title": "Stuck", "reason": "Upstream API" }],
  "done": [{ "id": "T-12", "title": "Per-task budget scope" }]
}
EOF
}

@test "parse-plan: stdout is TaskSpec JSON; stderr is task id" {
  write_plan
  out=$("$BIN" "$PLAN" 2>"$TEST_TMP/err")
  echo "$out" | jq -e '.' >/dev/null
  [ "$(echo "$out" | jq -r '.task_id')" = "T-42" ]
  [ "$(cat "$TEST_TMP/err")" = "T-42" ]
}

@test "parse-plan: per-item budget wins over defaults" {
  write_plan
  out=$("$BIN" "$PLAN" 2>/dev/null)
  [ "$(echo "$out" | jq '.budget.max_actions')" = "150" ]
  [ "$(echo "$out" | jq '.budget.timeout_seconds')" = "1200" ]
}

@test "parse-plan: defaults fill in when item omits budget/tools" {
  write_plan
  out=$("$BIN" "$PLAN" --task T-43 2>/dev/null)
  [ "$(echo "$out" | jq -r '.task_id')" = "T-43" ]
  [ "$(echo "$out" | jq '.budget.max_actions')" = "200" ]
  [ "$(echo "$out" | jq '.budget.timeout_seconds')" = "1800" ]
  [ "$(echo "$out" | jq -r '.allowed_tools | join(",")')" = "Read,Edit" ]
}

@test "parse-plan: goal falls back to title when goal is absent" {
  write_plan
  out=$("$BIN" "$PLAN" --task T-43 2>/dev/null)
  [ "$(echo "$out" | jq -r '.goal')" = "Followup" ]
}

@test "parse-plan: --bucket next selects next[0]" {
  write_plan
  out=$("$BIN" "$PLAN" --bucket next 2>/dev/null)
  [ "$(echo "$out" | jq -r '.task_id')" = "T-44" ]
}

@test "parse-plan: --bucket done is rejected" {
  write_plan
  run "$BIN" "$PLAN" --bucket done
  [ "$status" -eq 1 ]
  [[ "$output" == *"not selectable"* ]]
}

@test "parse-plan: blocked item via --bucket blocked exits 1 with reason" {
  write_plan
  run "$BIN" "$PLAN" --bucket blocked
  [ "$status" -eq 1 ]
  [[ "$output" == *"T-19"* ]]
  [[ "$output" == *"Upstream API"* ]]
}

@test "parse-plan: --task with id in different bucket fails (now-only by default)" {
  write_plan
  run "$BIN" "$PLAN" --task T-44
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"now"* ]]
}

@test "parse-plan: missing schema_version fails" {
  cat > "$PLAN" <<'EOF'
{ "now": [{"id":"T-1","title":"x"}], "next": [], "blocked": [], "done": [] }
EOF
  run "$BIN" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema"* ]]
}

@test "parse-plan: unsupported schema_version major fails" {
  cat > "$PLAN" <<'EOF'
{ "schema_version": "2.0", "now": [{"id":"T-1","title":"x"}], "next": [], "blocked": [], "done": [] }
EOF
  run "$BIN" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported"* ]]
}

@test "parse-plan: missing bucket fails" {
  cat > "$PLAN" <<'EOF'
{ "schema_version": "1.0", "now": [{"id":"T-1","title":"x"}], "blocked": [], "done": [] }
EOF
  run "$BIN" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"next"* ]]
}

@test "parse-plan: bucket wrong type fails" {
  cat > "$PLAN" <<'EOF'
{ "schema_version": "1.0", "now": {}, "next": [], "blocked": [], "done": [] }
EOF
  run "$BIN" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"now"* ]]
}

@test "parse-plan: empty now[] with no --task fails" {
  cat > "$PLAN" <<'EOF'
{ "schema_version": "1.0", "now": [], "next": [], "blocked": [], "done": [] }
EOF
  run "$BIN" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no candidate"* ]]
}

@test "parse-plan: --validate succeeds silently for a good plan" {
  write_plan
  run "$BIN" "$PLAN" --validate
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "parse-plan: --validate fails for broken plan" {
  echo "{ not json }" > "$PLAN"
  run "$BIN" "$PLAN" --validate
  [ "$status" -eq 1 ]
}

@test "parse-plan: LANEKEEP_PLAN_FILE substitutes for positional arg" {
  write_plan
  out=$(LANEKEEP_PLAN_FILE="$PLAN" "$BIN" 2>/dev/null)
  [ "$(echo "$out" | jq -r '.task_id')" = "T-42" ]
}

@test "parse-plan: no plan file and no env var exits 2" {
  run env -u LANEKEEP_PLAN_FILE "$BIN"
  [ "$status" -eq 2 ]
}

@test "parse-plan: nonexistent plan path exits 1" {
  run "$BIN" "$TEST_TMP/nope.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "parse-plan: item missing id fails" {
  cat > "$PLAN" <<'EOF'
{ "schema_version": "1.0", "now": [{"title":"x"}], "next": [], "blocked": [], "done": [] }
EOF
  run "$BIN" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"id"* ]]
}

@test "parse-plan: item missing title fails" {
  cat > "$PLAN" <<'EOF'
{ "schema_version": "1.0", "now": [{"id":"T-1"}], "next": [], "blocked": [], "done": [] }
EOF
  run "$BIN" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"title"* ]]
}

@test "parse-plan: denied_tools passthrough" {
  write_plan
  out=$("$BIN" "$PLAN" 2>/dev/null)
  [ "$(echo "$out" | jq -r '.denied_tools | join(",")')" = "WebFetch" ]
}

@test "parse-plan: unknown top-level key emits warning but succeeds" {
  cat > "$PLAN" <<'EOF'
{ "schema_version": "1.0", "weird_key": 42,
  "now": [{"id":"T-1","title":"x"}], "next": [], "blocked": [], "done": [] }
EOF
  out=$("$BIN" "$PLAN" 2>"$TEST_TMP/err")
  [ "$(echo "$out" | jq -r '.task_id')" = "T-1" ]
  grep -q "weird_key" "$TEST_TMP/err"
}

@test "parse-plan: output is forwardable to LANEKEEP_TASKSPEC_FILE" {
  write_plan
  "$BIN" "$PLAN" 2>/dev/null > "$TEST_TMP/taskspec.json"
  # Required TaskSpec fields exist and are correctly shaped
  jq -e '.task_id and .goal and (.allowed_tools | type == "array") and (.denied_tools | type == "array") and .budget' "$TEST_TMP/taskspec.json" >/dev/null
}
