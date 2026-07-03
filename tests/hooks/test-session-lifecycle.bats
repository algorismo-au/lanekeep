#!/usr/bin/env bats
# Tests for hooks/session-start.sh + hooks/pre-compact.sh
# and their registration in bin/lanekeep-init.

setup() {
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export LANEKEEP_DIR
  TEST_TMP="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMP/project"
  mkdir -p "$PROJECT_DIR/.lanekeep/traces"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$PROJECT_DIR/lanekeep.json"
  export LANEKEEP_CONFIG_FILE="$PROJECT_DIR/lanekeep.json"
  export LANEKEEP_SESSION_ID="test-lifecycle-$$"
  export LANEKEEP_TRACE_FILE="$PROJECT_DIR/.lanekeep/traces/${LANEKEEP_SESSION_ID}.jsonl"
}

teardown() {
  rm -rf "$TEST_TMP"
  return 0
}

# ────────────────────────────────────────────────
# hooks/session-start.sh
# ────────────────────────────────────────────────

@test "session-start: exit 0 with no memory files present" {
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, source:"startup"}')
  run bash -c "'$LANEKEEP_DIR/hooks/session-start.sh' <<< '$input'"
  [ "$status" -eq 0 ]
}

@test "session-start: exit 0 on source=clear (skips scan)" {
  # Even with an injected CLAUDE.md, source=clear must skip.
  printf 'prefix\x1b[31mhidden\x1b[0msuffix' > "$PROJECT_DIR/CLAUDE.md"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, source:"clear"}')
  run bash -c "'$LANEKEEP_DIR/hooks/session-start.sh' <<< '$input'"
  [ "$status" -eq 0 ]
  # No policy events should be written when scan is skipped
  [ ! -f "$LANEKEEP_TRACE_FILE" ] || ! grep -q "session_start" "$LANEKEEP_TRACE_FILE"
}

@test "session-start: clean CLAUDE.md yields session_start marker in trace" {
  printf 'A benign CLAUDE.md with no injection markers.\n' > "$PROJECT_DIR/CLAUDE.md"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, source:"startup"}')
  "$LANEKEEP_DIR/hooks/session-start.sh" <<< "$input"
  [ -f "$LANEKEEP_TRACE_FILE" ]
  grep -q '"event":"session_start"' "$LANEKEEP_TRACE_FILE"
}

@test "session-start: ANSI-escape CLAUDE.md yields a hidden_text finding" {
  printf 'prefix\x1b[31minjected\x1b[0msuffix' > "$PROJECT_DIR/CLAUDE.md"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, source:"resume"}')
  run bash -c "'$LANEKEEP_DIR/hooks/session-start.sh' <<< '$input' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE.md"* ]]
  # Trace should carry a session_start_scan event
  grep -q '"event":"session_start_scan"' "$LANEKEEP_TRACE_FILE"
}

@test "session-start: scan_memory=false skips work" {
  jq '.hooks.session_start.scan_memory = false' "$LANEKEEP_CONFIG_FILE" \
    > "$LANEKEEP_CONFIG_FILE.tmp" && mv "$LANEKEEP_CONFIG_FILE.tmp" "$LANEKEEP_CONFIG_FILE"
  printf 'prefix\x1b[31mhidden\x1b[0msuffix' > "$PROJECT_DIR/CLAUDE.md"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, source:"startup"}')
  "$LANEKEEP_DIR/hooks/session-start.sh" <<< "$input"
  # No trace events when disabled
  [ ! -f "$LANEKEEP_TRACE_FILE" ] || ! grep -q "session_start" "$LANEKEEP_TRACE_FILE"
}

@test "session-start: scans .claude/instructions/*.md" {
  mkdir -p "$PROJECT_DIR/.claude/instructions"
  printf 'prefix\x1b[31mhidden\x1b[0msuffix' > "$PROJECT_DIR/.claude/instructions/agent.md"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, source:"resume"}')
  "$LANEKEEP_DIR/hooks/session-start.sh" <<< "$input" 2>/dev/null
  grep -q '"event":"session_start_scan"' "$LANEKEEP_TRACE_FILE"
}

# ────────────────────────────────────────────────
# hooks/pre-compact.sh
# ────────────────────────────────────────────────

@test "pre-compact: creates snapshot file with expected schema" {
  echo '{"total_events": 42, "input_tokens": 1000}' > "$PROJECT_DIR/.lanekeep/cumulative.json"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, trigger:"auto"}')
  "$LANEKEEP_DIR/hooks/pre-compact.sh" <<< "$input"
  local snap
  snap=$(find "$PROJECT_DIR/.lanekeep/compaction-snapshots" -type f -name '*.json' | head -1)
  [ -n "$snap" ]
  [ -f "$snap" ]
  [ "$(jq -r '.schema' "$snap")" = "lanekeep.compaction-snapshot/v1" ]
  [ "$(jq -r '.session_id' "$snap")" = "$LANEKEEP_SESSION_ID" ]
  [ "$(jq -r '.trigger' "$snap")" = "auto" ]
}

@test "pre-compact: preserves cumulative.json contents in snapshot" {
  echo '{"total_events": 42, "input_tokens": 1000, "output_tokens": 500}' \
    > "$PROJECT_DIR/.lanekeep/cumulative.json"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, trigger:"manual"}')
  "$LANEKEEP_DIR/hooks/pre-compact.sh" <<< "$input"
  local snap
  snap=$(find "$PROJECT_DIR/.lanekeep/compaction-snapshots" -type f -name '*.json' | head -1)
  [ "$(jq '.cumulative.total_events' "$snap")" = "42" ]
  [ "$(jq '.cumulative.input_tokens' "$snap")" = "1000" ]
  [ "$(jq '.cumulative.output_tokens' "$snap")" = "500" ]
}

@test "pre-compact: missing cumulative.json → null in snapshot" {
  # Do NOT create cumulative.json
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, trigger:"auto"}')
  "$LANEKEEP_DIR/hooks/pre-compact.sh" <<< "$input"
  local snap
  snap=$(find "$PROJECT_DIR/.lanekeep/compaction-snapshots" -type f -name '*.json' | head -1)
  [ -n "$snap" ]
  [ "$(jq -r '.cumulative' "$snap")" = "null" ]
}

@test "pre-compact: logs snapshot event to trace" {
  echo '{"total_events": 1}' > "$PROJECT_DIR/.lanekeep/cumulative.json"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, trigger:"auto"}')
  "$LANEKEEP_DIR/hooks/pre-compact.sh" <<< "$input"
  [ -f "$LANEKEEP_TRACE_FILE" ]
  grep -q '"event":"pre_compact_snapshot"' "$LANEKEEP_TRACE_FILE"
}

@test "pre-compact: snapshot=false skips work" {
  jq '.hooks.pre_compact.snapshot = false' "$LANEKEEP_CONFIG_FILE" \
    > "$LANEKEEP_CONFIG_FILE.tmp" && mv "$LANEKEEP_CONFIG_FILE.tmp" "$LANEKEEP_CONFIG_FILE"
  echo '{"total_events": 1}' > "$PROJECT_DIR/.lanekeep/cumulative.json"
  input=$(jq -n --arg cwd "$PROJECT_DIR" --arg sid "$LANEKEEP_SESSION_ID" \
    '{cwd:$cwd, session_id:$sid, trigger:"auto"}')
  "$LANEKEEP_DIR/hooks/pre-compact.sh" <<< "$input"
  # No snapshot dir when disabled
  [ ! -d "$PROJECT_DIR/.lanekeep/compaction-snapshots" ]
}

@test "pre-compact: exit 0 with completely empty input" {
  run bash -c "'$LANEKEEP_DIR/hooks/pre-compact.sh' <<< ''"
  [ "$status" -eq 0 ]
}

# ────────────────────────────────────────────────
# lanekeep-init installs both hooks
# ────────────────────────────────────────────────

@test "init: installs SessionStart hook" {
  local init_dir="$TEST_TMP/init-ss"
  mkdir -p "$init_dir"
  "$LANEKEEP_DIR/bin/lanekeep-init" "$init_dir" >/dev/null
  jq -e '.hooks.SessionStart' "$init_dir/.claude/settings.local.json" >/dev/null
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$init_dir/.claude/settings.local.json")
  [[ "$cmd" == *"session-start.sh" ]]
}

@test "init: installs PreCompact hook" {
  local init_dir="$TEST_TMP/init-pc"
  mkdir -p "$init_dir"
  "$LANEKEEP_DIR/bin/lanekeep-init" "$init_dir" >/dev/null
  jq -e '.hooks.PreCompact' "$init_dir/.claude/settings.local.json" >/dev/null
  cmd=$(jq -r '.hooks.PreCompact[0].hooks[0].command' "$init_dir/.claude/settings.local.json")
  [[ "$cmd" == *"pre-compact.sh" ]]
}

@test "init: idempotent — second run skips SessionStart + PreCompact" {
  local init_dir="$TEST_TMP/init-idem"
  mkdir -p "$init_dir"
  "$LANEKEEP_DIR/bin/lanekeep-init" "$init_dir" >/dev/null
  result=$("$LANEKEEP_DIR/bin/lanekeep-init" "$init_dir" 2>&1)
  [[ "$result" == *"SessionStart hook already installed"* ]]
  [[ "$result" == *"PreCompact hook already installed"* ]]
  # Still exactly one of each
  ss_count=$(jq '.hooks.SessionStart | length' "$init_dir/.claude/settings.local.json")
  pc_count=$(jq '.hooks.PreCompact | length' "$init_dir/.claude/settings.local.json")
  [ "$ss_count" -eq 1 ]
  [ "$pc_count" -eq 1 ]
}

@test "init: appends to existing team-shared SessionStart" {
  local init_dir="$TEST_TMP/init-append"
  mkdir -p "$init_dir/.claude"
  # Simulate a team-shared SessionStart hook already present
  cat > "$init_dir/.claude/settings.local.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {"matcher": "", "hooks": [{"type": "command", "command": "/team/orient.sh", "timeout": 5000}]}
    ]
  }
}
JSON
  "$LANEKEEP_DIR/bin/lanekeep-init" "$init_dir" >/dev/null
  count=$(jq '.hooks.SessionStart | length' "$init_dir/.claude/settings.local.json")
  [ "$count" -eq 2 ]
  # Existing team hook preserved
  team_cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$init_dir/.claude/settings.local.json")
  [ "$team_cmd" = "/team/orient.sh" ]
  # LaneKeep hook appended
  our_cmd=$(jq -r '.hooks.SessionStart[1].hooks[0].command' "$init_dir/.claude/settings.local.json")
  [[ "$our_cmd" == *"session-start.sh" ]]
}
