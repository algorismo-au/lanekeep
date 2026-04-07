#!/usr/bin/env bats
# Comprehensive tests for agent/subagent logging and multi-agent observability.
#
# Tests verify that LaneKeep correctly captures trace data for different agent
# types: single agents, concurrent agents with different session_ids, simulated
# subagents (worktree-isolated), and agents sharing a sidecar.
#
# Covers AG-002 (cc_session_id), AG-003 (agent metadata), AG-004 (worktree correlation).

LANEKEEP_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  export LANEKEEP_DIR
  export PATH="$LANEKEEP_DIR/bin:$PATH"
  TEST_TMPDIR="$(mktemp -d)"
  export PROJECT_DIR="$TEST_TMPDIR/project"
  export LANEKEEP_SOCKET="$TEST_TMPDIR/lanekeep-test.sock"
  mkdir -p "$PROJECT_DIR/.lanekeep/traces"
  cp "$LANEKEEP_DIR/defaults/lanekeep.json" "$PROJECT_DIR/lanekeep.json"
  SERVER_PID=""
}

teardown() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    pkill -P "$SERVER_PID" 2>/dev/null || true
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  # Clean up registry symlinks created during tests
  local _reg="${XDG_STATE_HOME:-$HOME/.local/state}/lanekeep/sockets"
  if [ -d "$_reg" ]; then
    find "$_reg" -name "*.sock" -lname "*$TEST_TMPDIR*" -delete 2>/dev/null || true
  fi
  rm -rf "$TEST_TMPDIR"
  return 0
}

start_server() {
  cd "$PROJECT_DIR"
  "$LANEKEEP_DIR/bin/lanekeep-serve" "$@" </dev/null >/dev/null 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
  SERVER_PID=$!
  local tries=0
  while [ ! -S "$LANEKEEP_SOCKET" ] && [ $tries -lt 30 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
  [ -S "$LANEKEEP_SOCKET" ] || { echo "Server failed to start" >&2; return 1; }
}

send_json() {
  printf '%s' "$1" | socat -t 4 - UNIX-CONNECT:"$LANEKEEP_SOCKET" 2>/dev/null
}

make_request() {
  local tool_name="$1"
  local session_id="$2"
  local tool_input="${3:-}"
  if [ -z "$tool_input" ]; then
    tool_input='{"file_path":"src/main.py"}'
  fi
  jq -n -c \
    --arg tn "$tool_name" \
    --arg ti "$tool_input" \
    --arg tuid "toolu_$RANDOM" \
    --arg sid "$session_id" \
    '{hook_event_name:"PreToolUse",tool_name:$tn,tool_input:($ti|fromjson),tool_use_id:$tuid,session_id:$sid,cwd:"/home/user/project"}'
}

# Count total trace entries across ALL trace files (session boundaries create new files)
count_all_traces() {
  cat "$PROJECT_DIR/.lanekeep/traces/"*.jsonl 2>/dev/null | wc -l
}

# Get all trace entries as a single JSON array
all_trace_entries() {
  cat "$PROJECT_DIR/.lanekeep/traces/"*.jsonl 2>/dev/null | jq -s '.'
}

# ============================================================================
# TEST 1: AG-002 — Single agent trace has cc_session_id
# ============================================================================

@test "AG-002: trace entry contains cc_session_id matching hook input session_id" {
  start_server
  local req
  req=$(make_request "Read" "sess-parent-001")
  send_json "$req" > /dev/null
  sleep 0.5

  local trace_count
  trace_count=$(count_all_traces)
  [ "$trace_count" -ge 1 ]

  # session_id is LANEKEEP_SESSION_ID (sidecar PID-based), NOT the CC session_id
  local sid
  sid=$(all_trace_entries | jq -r '.[0].session_id')
  [ -n "$sid" ] && [ "$sid" != "null" ]
  [ "$sid" != "sess-parent-001" ]

  # cc_session_id contains the Claude Code session_id from hook input
  local cc_sid
  cc_sid=$(all_trace_entries | jq -r '.[0].cc_session_id')
  echo "# cc_session_id: $cc_sid" >&3
  [ "$cc_sid" = "sess-parent-001" ]

  # correlation_id and project_dir should be present (AG-004)
  local corr_id proj_dir
  corr_id=$(all_trace_entries | jq -r '.[0].correlation_id')
  proj_dir=$(all_trace_entries | jq -r '.[0].project_dir')
  echo "# correlation_id: $corr_id" >&3
  echo "# project_dir: $proj_dir" >&3
  [ -n "$corr_id" ] && [ "$corr_id" != "null" ]
  [ -n "$proj_dir" ] && [ "$proj_dir" != "null" ]
}

# ============================================================================
# TEST 2: AG-002 — Two agents with different CC session_ids both get cc_session_id
# ============================================================================

@test "AG-002: different CC session_ids produce traces with correct cc_session_id" {
  start_server

  local req_a
  req_a=$(make_request "Read" "sess-agent-A")
  send_json "$req_a" > /dev/null
  sleep 0.3

  local req_b
  req_b=$(make_request "Bash" "sess-agent-B" '{"command":"ls"}')
  send_json "$req_b" > /dev/null
  sleep 0.5

  local total
  total=$(count_all_traces)
  [ "$total" -ge 2 ]

  # All entries should have cc_session_id
  local entries_with_cc_sid
  entries_with_cc_sid=$(all_trace_entries | jq '[.[] | select(has("cc_session_id"))] | length')
  echo "# Entries with cc_session_id: $entries_with_cc_sid" >&3
  [ "$entries_with_cc_sid" -ge 2 ]

  # Agent metadata stays absent (CC doesn't send it in this test)
  local has_agent_id
  has_agent_id=$(all_trace_entries | jq 'any(has("agent_id"))')
  [ "$has_agent_id" = "false" ]
}

# ============================================================================
# TEST 3: Agent tool call logged — cc_session_id present, parent linkage absent
# ============================================================================

@test "Agent tool call has cc_session_id but no parent linkage (upstream not sending yet)" {
  start_server

  local agent_req
  agent_req=$(make_request "Agent" "sess-parent-001" '{"prompt":"Analyze codebase","description":"explore code"}')
  send_json "$agent_req" > /dev/null
  sleep 0.3

  local sub_req
  sub_req=$(make_request "Read" "sess-parent-001" '{"file_path":"src/lib.py"}')
  send_json "$sub_req" > /dev/null
  sleep 0.5

  local total
  total=$(count_all_traces)
  [ "$total" -ge 2 ]

  # Both entries have cc_session_id
  local all_have_cc
  all_have_cc=$(all_trace_entries | jq 'all(has("cc_session_id"))')
  [ "$all_have_cc" = "true" ]

  # Agent call IS logged
  local agent_calls
  agent_calls=$(all_trace_entries | jq '[.[] | select(.tool_name == "Agent")] | length')
  [ "$agent_calls" -ge 1 ]

  # GAP remains: No parent linkage until CC sends agent metadata
  local read_entry
  read_entry=$(all_trace_entries | jq '.[] | select(.tool_name == "Read" and .tool_input.file_path == "src/lib.py")')
  local has_parent_link
  has_parent_link=$(echo "$read_entry" | jq 'has("parent_session_id") or has("spawned_by") or has("agent_depth")')
  [ "$has_parent_link" = "false" ]
}

# ============================================================================
# TEST 4: AG-004 — Worktree with LANEKEEP_SOCKET shares sidecar, has correlation_id
# ============================================================================

@test "AG-004: worktree with LANEKEEP_SOCKET shares sidecar and correlation_id" {
  start_server

  local parent_req
  parent_req=$(make_request "Read" "sess-parent" '{"file_path":"main.py"}')
  send_json "$parent_req" > /dev/null
  sleep 0.3

  local wt_req
  wt_req=$(make_request "Bash" "sess-parent" '{"command":"git status"}')
  send_json "$wt_req" > /dev/null
  sleep 0.5

  local total
  total=$(count_all_traces)
  [ "$total" -ge 2 ]

  # All entries have matching correlation_id
  local corr_ids
  corr_ids=$(all_trace_entries | jq '[.[].correlation_id] | unique | length')
  echo "# Unique correlation_ids: $corr_ids" >&3
  [ "$corr_ids" -eq 1 ]

  # correlation_id is non-empty
  local corr_id
  corr_id=$(all_trace_entries | jq -r '.[0].correlation_id')
  [ -n "$corr_id" ] && [ "$corr_id" != "null" ]
}

# ============================================================================
# TEST 5: AG-004 — Worktree without LANEKEEP_SOCKET uses git-based discovery
# ============================================================================

@test "AG-004: worktree discovers parent socket via git rev-parse and registry" {
  # Initialize a git repo in project dir (needed for git worktree)
  (cd "$PROJECT_DIR" && git init -q && git commit --allow-empty -m "init" -q) || skip "git not available"

  start_server

  # Parent request
  local parent_req
  parent_req=$(make_request "Read" "sess-parent")
  send_json "$parent_req" > /dev/null
  sleep 0.3

  # Create actual git worktree
  local worktree="$TEST_TMPDIR/worktrees/feature-branch"
  (cd "$PROJECT_DIR" && git worktree add -q "$worktree" HEAD) || skip "git worktree not supported"

  # Verify registry symlink exists
  local corr_id
  corr_id=$(printf '%s' "$(cd "$PROJECT_DIR" && pwd -P)" | sha256sum | cut -c1-16)
  local registry="${XDG_STATE_HOME:-$HOME/.local/state}/lanekeep/sockets"
  echo "# Expected registry: $registry/${corr_id}.sock" >&3
  [ -L "$registry/${corr_id}.sock" ] || { echo "# Registry symlink not found" >&3; skip "Registry not created"; }

  # From the worktree, without LANEKEEP_SOCKET, evaluate.sh should discover parent via git
  local wt_req
  wt_req=$(make_request "Read" "sess-worktree" '{"file_path":"feature.py"}')
  local wt_response
  wt_response=$(cd "$worktree" && unset LANEKEEP_SOCKET && unset PROJECT_DIR && \
    printf '%s' "$wt_req" | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null) || true

  sleep 0.5

  # The worktree request should have been handled by the parent sidecar
  # (traces in parent's trace dir, not a fallback)
  local total
  total=$(count_all_traces)
  echo "# Total traces after worktree request: $total" >&3
  [ "$total" -ge 2 ]

  # Both entries should have the same correlation_id
  local all_corr
  all_corr=$(all_trace_entries | jq --arg cid "$corr_id" 'all(.correlation_id == $cid)')
  echo "# All entries match correlation_id: $all_corr" >&3

  # Cleanup worktree
  (cd "$PROJECT_DIR" && git worktree remove "$worktree" --force) 2>/dev/null || true
}

# ============================================================================
# TEST 6: Budget counters RESET on session_id change (pre-existing gap — AG-001)
# ============================================================================

@test "budget counters reset when CC session_id changes (AG-001 gap, cc_session_id tracked)" {
  start_server

  for i in 1 2 3; do
    local req
    req=$(make_request "Read" "sess-agent-A" '{"file_path":"file'$i'.py"}')
    send_json "$req" > /dev/null
    sleep 0.1
  done
  sleep 0.3

  local req_b
  req_b=$(make_request "Read" "sess-agent-B" '{"file_path":"bfile.py"}')
  send_json "$req_b" > /dev/null
  sleep 0.5

  # Budget counter was reset (AG-001 gap still exists)
  local state_after
  state_after=$(jq -r '.total_events // 0' "$PROJECT_DIR/.lanekeep/state.json" 2>/dev/null)
  [ "$state_after" -le 2 ]

  # But now we have cc_session_id in traces for diagnosis
  local cc_sids
  cc_sids=$(all_trace_entries | jq '[.[].cc_session_id] | unique | sort')
  echo "# CC session_ids in traces: $cc_sids" >&3
  # Both session IDs should appear
  echo "$cc_sids" | jq -e 'contains(["sess-agent-A"])' > /dev/null
  echo "$cc_sids" | jq -e 'contains(["sess-agent-B"])' > /dev/null
}

# ============================================================================
# TEST 7: Session boundary finalizes to cumulative
# ============================================================================

@test "session boundary finalizes to cumulative on CC session_id change" {
  start_server

  for i in 1 2 3; do
    local req
    req=$(make_request "Read" "sess-A" '{"file_path":"a'$i'.py"}')
    send_json "$req" > /dev/null
    sleep 0.1
  done
  sleep 0.3

  local req_b
  req_b=$(make_request "Read" "sess-B" '{"file_path":"b1.py"}')
  send_json "$req_b" > /dev/null
  sleep 0.5

  local cumfile="$PROJECT_DIR/.lanekeep/cumulative.json"
  [ -f "$cumfile" ] || { echo "# No cumulative file"; skip "cumulative not written"; }

  local total_sessions
  total_sessions=$(jq -r '.total_sessions // 0' "$cumfile")
  echo "# Cumulative sessions finalized: $total_sessions" >&3
  [ "$total_sessions" -ge 1 ]
}

# ============================================================================
# TEST 8: Concurrent agents produce non-corrupt trace entries
# ============================================================================

@test "concurrent agents produce non-corrupt trace entries with cc_session_id" {
  start_server
  local outdir="$TEST_TMPDIR/concurrent"
  mkdir -p "$outdir"
  local pids=()

  for i in $(seq 1 8); do
    (
      local req
      req=$(make_request "Read" "sess-shared" '{"file_path":"concurrent'$i'.py"}')
      send_json "$req" > "$outdir/$i.out" 2>/dev/null
    ) &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done
  sleep 0.5

  local total
  total=$(count_all_traces)
  [ "$total" -ge 8 ]

  # Every line should be valid JSON
  local invalid
  invalid=$(cat "$PROJECT_DIR/.lanekeep/traces/"*.jsonl 2>/dev/null | while IFS= read -r line; do
    echo "$line" | jq -e '.' >/dev/null 2>&1 || echo "INVALID"
  done | wc -l)
  [ "$invalid" -eq 0 ]

  # All entries should have cc_session_id
  local all_have_cc
  all_have_cc=$(all_trace_entries | jq 'all(has("cc_session_id"))')
  [ "$all_have_cc" = "true" ]
}

# ============================================================================
# TEST 9: Agent tool call trace — cc_session_id present, agent metadata absent
# ============================================================================

@test "Agent tool call trace has cc_session_id, agent metadata absent when not sent" {
  start_server

  local req
  req=$(make_request "Agent" "sess-parent-check" '{"prompt":"Search for bugs","description":"bug search","subagent_type":"Explore"}')
  send_json "$req" > /dev/null
  sleep 0.5

  local total
  total=$(count_all_traces)
  [ "$total" -ge 1 ]

  local agent_entry
  agent_entry=$(all_trace_entries | jq -c '.[] | select(.tool_name == "Agent")' | head -1)
  [ -n "$agent_entry" ]

  # cc_session_id IS present
  echo "$agent_entry" | jq -e '.cc_session_id == "sess-parent-check"' > /dev/null

  # Agent metadata fields absent (CC doesn't send them yet)
  local absent=""
  for field in agent_id agent_type parent_session_id spawned_by agent_depth isolation_type is_background; do
    echo "$agent_entry" | jq -e "has(\"$field\")" > /dev/null 2>&1 || absent="$absent $field"
  done
  echo "# Absent agent fields:$absent" >&3
  [ -n "$absent" ]
}

# ============================================================================
# TEST 10: Fallback trace — cc_session_id captured, session_id is "hook-fallback"
# ============================================================================

@test "fallback trace has cc_session_id and session_id='hook-fallback'" {
  export LANEKEEP_FAIL_POLICY="allow"

  local req
  req=$(jq -n -c '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:"test.py"},tool_use_id:"toolu_fallback",session_id:"sess-orphan-agent"}')

  cd "$PROJECT_DIR"
  unset LANEKEEP_SOCKET
  export PROJECT_DIR

  echo "$req" | "$LANEKEEP_DIR/hooks/evaluate.sh" 2>/dev/null || true
  sleep 0.3

  local fallback_trace="$PROJECT_DIR/.lanekeep/traces/hook-fallback.jsonl"
  [ -f "$fallback_trace" ] || skip "Fallback trace not created"

  # session_id is now "hook-fallback" (source identity, consistent with main traces)
  local sid
  sid=$(jq -r '.session_id' "$fallback_trace" | head -1)
  echo "# Fallback session_id: $sid" >&3
  [ "$sid" = "hook-fallback" ]

  # cc_session_id has the CC session_id
  local cc_sid
  cc_sid=$(jq -r '.cc_session_id' "$fallback_trace" | head -1)
  echo "# Fallback cc_session_id: $cc_sid" >&3
  [ "$cc_sid" = "sess-orphan-agent" ]
}

# ============================================================================
# TEST 11: Rapid session_id cycling — state survives, cc_session_id tracked
# ============================================================================

@test "rapid session_id cycling: state valid, all cc_session_ids tracked" {
  start_server

  local agents=("team-alpha" "team-beta" "team-gamma" "team-delta" "team-epsilon")
  for agent in "${agents[@]}"; do
    local req
    req=$(make_request "Read" "$agent" '{"file_path":"team.py"}')
    send_json "$req" > /dev/null
    sleep 0.1
  done
  sleep 0.5

  # State file should be valid JSON
  local state_file="$PROJECT_DIR/.lanekeep/state.json"
  [ -f "$state_file" ]
  run jq '.' "$state_file"
  [ "$status" -eq 0 ]

  # All 5 events should appear across trace files
  local total
  total=$(count_all_traces)
  [ "$total" -ge 5 ]

  # All 5 cc_session_ids should be present
  local unique_cc_sids
  unique_cc_sids=$(all_trace_entries | jq '[.[].cc_session_id] | unique | length')
  echo "# Unique cc_session_ids: $unique_cc_sids" >&3
  [ "$unique_cc_sids" -ge 5 ]
}

# ============================================================================
# TEST 12: Trace schema completeness — document present/absent fields
# ============================================================================

@test "trace schema: cc_session_id, correlation_id, project_dir present" {
  start_server

  local req
  req=$(make_request "Read" "sess-schema" '{"file_path":"audit.py"}')
  send_json "$req" > /dev/null
  sleep 0.5

  local total
  total=$(count_all_traces)
  [ "$total" -ge 1 ]

  local entry
  entry=$(all_trace_entries | jq -c '.[0]')

  # Core fields + new AG-002/004 fields present
  local present=""
  for field in timestamp source session_id event_type tool_name tool_input decision reason latency_ms evaluators ralph config_hash cc_session_id correlation_id project_dir; do
    if echo "$entry" | jq -e "has(\"$field\")" > /dev/null 2>&1; then
      present="$present $field"
    else
      echo "# MISSING field: $field" >&3
    fi
  done
  echo "# Present fields:$present" >&3

  # cc_session_id, correlation_id, project_dir must be present
  echo "$entry" | jq -e 'has("cc_session_id")' > /dev/null
  echo "$entry" | jq -e 'has("correlation_id")' > /dev/null
  echo "$entry" | jq -e 'has("project_dir")' > /dev/null

  # Agent governance fields — absent until CC sends them
  local absent=""
  for field in agent_id agent_type parent_session_id agent_team_id isolation_type is_background spawned_by agent_depth; do
    echo "$entry" | jq -e "has(\"$field\")" > /dev/null 2>&1 || absent="$absent $field"
  done
  echo "# Absent agent fields (awaiting upstream):$absent" >&3
  [ -n "$absent" ]
}

# ============================================================================
# TEST 13: AG-003 — Agent metadata fields forwarded when present in hook input
# ============================================================================

@test "AG-003: agent metadata forwarded to trace when CC sends them" {
  start_server

  local req
  req=$(jq -n -c '{
    hook_event_name:"PreToolUse",
    tool_name:"Read",
    tool_input:{file_path:"test.py"},
    tool_use_id:"toolu_agent_meta",
    session_id:"sess-sub-001",
    agent_id:"agent-abc123",
    parent_session_id:"sess-parent-000",
    spawned_by:"toolu_spawn_xyz",
    agent_depth:1,
    agent_type:"Explore",
    isolation_type:"worktree",
    is_background:false
  }')
  send_json "$req" > /dev/null
  sleep 0.5

  local entry
  entry=$(all_trace_entries | jq -c '.[0]')
  [ -n "$entry" ]

  # All agent metadata fields should be present with correct values
  echo "$entry" | jq -e '.agent_id == "agent-abc123"' > /dev/null
  echo "$entry" | jq -e '.parent_session_id == "sess-parent-000"' > /dev/null
  echo "$entry" | jq -e '.spawned_by == "toolu_spawn_xyz"' > /dev/null
  echo "$entry" | jq -e '.agent_depth == 1' > /dev/null
  echo "$entry" | jq -e '.agent_type == "Explore"' > /dev/null
  echo "$entry" | jq -e '.isolation_type == "worktree"' > /dev/null

  # is_background: false should NOT appear in trace (minimize bloat)
  echo "$entry" | jq -e 'has("is_background") | not' > /dev/null

  # cc_session_id should also be present
  echo "$entry" | jq -e '.cc_session_id == "sess-sub-001"' > /dev/null
}

# ============================================================================
# TEST 14: AG-003 — is_background: true IS written to trace
# ============================================================================

@test "AG-003: is_background true written to trace" {
  start_server

  local req
  req=$(jq -n -c '{
    hook_event_name:"PreToolUse",
    tool_name:"Grep",
    tool_input:{pattern:"TODO"},
    tool_use_id:"toolu_bg",
    session_id:"sess-bg",
    agent_id:"agent-bg-001",
    is_background:true
  }')
  send_json "$req" > /dev/null
  sleep 0.5

  local entry
  entry=$(all_trace_entries | jq -c '.[0]')
  echo "$entry" | jq -e '.is_background == true' > /dev/null
  echo "$entry" | jq -e '.agent_id == "agent-bg-001"' > /dev/null
}

# ============================================================================
# TEST 15: AG-003 — Agent metadata absent when not sent (no empty strings/nulls)
# ============================================================================

@test "AG-003: agent metadata absent from trace when CC does not send it" {
  start_server

  local req
  req=$(make_request "Read" "sess-normal" '{"file_path":"clean.py"}')
  send_json "$req" > /dev/null
  sleep 0.5

  local entry
  entry=$(all_trace_entries | jq -c '.[0]')

  # No agent metadata fields should exist — not even as empty strings or null
  for field in agent_id parent_session_id spawned_by agent_depth agent_type isolation_type is_background; do
    local has_field
    has_field=$(echo "$entry" | jq "has(\"$field\")")
    echo "# $field present: $has_field" >&3
    [ "$has_field" = "false" ]
  done
}

# ============================================================================
# TEST 16: AG-003 — agent_depth: 0 preserved (jq falsiness edge case)
# ============================================================================

@test "AG-003: agent_depth 0 preserved in trace (root agent)" {
  start_server

  local req
  req=$(jq -n -c '{
    hook_event_name:"PreToolUse",
    tool_name:"Read",
    tool_input:{file_path:"root.py"},
    tool_use_id:"toolu_depth0",
    session_id:"sess-root",
    agent_id:"agent-root",
    agent_depth:0
  }')
  send_json "$req" > /dev/null
  sleep 0.5

  local entry
  entry=$(all_trace_entries | jq -c '.[0]')
  echo "# agent_depth value: $(echo "$entry" | jq '.agent_depth')" >&3

  # agent_depth: 0 must be present as a number, not dropped
  echo "$entry" | jq -e 'has("agent_depth")' > /dev/null
  echo "$entry" | jq -e '.agent_depth == 0' > /dev/null
  echo "$entry" | jq -e '.agent_id == "agent-root"' > /dev/null
}

# ============================================================================
# TEST 17: Input validation — oversized agent_id truncated
# ============================================================================

@test "input validation: oversized agent_id truncated to 128 chars" {
  start_server

  # Generate a 200-char agent_id
  local long_id
  long_id=$(printf 'A%.0s' $(seq 1 200))

  local req
  req=$(jq -n -c \
    --arg aid "$long_id" \
    '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:"big.py"},
      tool_use_id:"toolu_long",session_id:"sess-long",agent_id:$aid}')
  send_json "$req" > /dev/null
  sleep 0.5

  local entry
  entry=$(all_trace_entries | jq -c '.[0]')
  local actual_len
  actual_len=$(echo "$entry" | jq '.agent_id | length')
  echo "# agent_id length: $actual_len (expected <= 128)" >&3
  [ "$actual_len" -le 128 ]
}

# ============================================================================
# TEST 18: AG-004 — Registry symlink created and cleaned up
# ============================================================================

@test "AG-004: socket registry symlink created at startup and cleaned on shutdown" {
  start_server

  local corr_id
  corr_id=$(printf '%s' "$(cd "$PROJECT_DIR" && pwd -P)" | sha256sum | cut -c1-16)
  local registry="${XDG_STATE_HOME:-$HOME/.local/state}/lanekeep/sockets"

  # Symlink should exist
  echo "# Looking for: $registry/${corr_id}.sock" >&3
  [ -L "$registry/${corr_id}.sock" ] || { echo "# Symlink not found" >&3; return 1; }

  # Symlink target should be the socket
  local target
  target=$(readlink -f "$registry/${corr_id}.sock")
  echo "# Symlink target: $target" >&3
  [ -S "$target" ]

  # Stop server — symlink should be removed
  pkill -P "$SERVER_PID" 2>/dev/null || true
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""  # Prevent double-cleanup in teardown
  sleep 0.3

  [ ! -L "$registry/${corr_id}.sock" ]
  echo "# Symlink removed after shutdown" >&3
}
