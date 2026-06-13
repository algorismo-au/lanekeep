#!/usr/bin/env bats
# Write-then-execute attack detection tests
# Layer 1: sys-033 flags script execution by interpreter (stateless)
# Layer 2: Session write-tracking escalates to deny when file was written this session

load ../test_helper

setup()    { setup_rules_env; }
teardown() { teardown_rules_env; }

# ============================================================================
# Layer 1: sys-033 — script execution by interpreter (ask)
# ============================================================================

@test "sys-033: bash /tmp/exploit.sh triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"bash /tmp/exploit.sh"}' || true
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"Script execution from non-project path"* ]]
}

@test "sys-033: sh /tmp/setup.sh triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"sh /tmp/setup.sh"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: python3 /tmp/script.py triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"python3 /tmp/script.py"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: node /tmp/payload.js triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"node /tmp/payload.js"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: ruby ~/script.rb triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"ruby ~/script.rb"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: perl /var/tmp/script.pl triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"perl /var/tmp/script.pl"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: bash ~/exploit.sh triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"bash ~/exploit.sh"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: source /tmp/malicious.sh triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"source /tmp/malicious.sh"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: dash /opt/script.sh triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"dash /opt/script.sh"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: php /tmp/exploit.php triggers ask" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"php /tmp/exploit.php"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "sys-033: plain ls command does not trigger" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"ls -la"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "sys-033: git status does not trigger" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"git status"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "sys-033: npm test does not trigger" {
  _isolate_rules "sys-033"
  rules_eval "Bash" '{"command":"npm test"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "sys-033: Write tool does not trigger sys-033" {
  _isolate_rules "sys-033"
  rules_eval "Write" '{"file_path":"/tmp/test.sh","content":"#!/bin/bash\necho hi"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# Layer 2: Session write-tracking — check_session_written_file()
# ============================================================================

# Helper: write a fake trace entry for a Write tool call
_write_trace_entry() {
  local file_path="$1"
  local decision="${2:-allow}"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"test"},"decision":"%s","file_path":"%s","timestamp":"2026-01-01T00:00:00Z","session_id":"test-session"}\n' \
    "$file_path" "$decision" "$file_path" >> "$LANEKEEP_TRACE_FILE"
}

@test "session-write-check: detects execution of session-written file by full path" {
  _write_trace_entry "/home/user/project/exploit.sh"
  check_session_written_file "Bash" '{"command":"bash /home/user/project/exploit.sh"}'
  [ "$SESSION_WRITE_EXEC_MATCHED" = "true" ]
  [ "$SESSION_WRITE_EXEC_FILE" = "/home/user/project/exploit.sh" ]
}

@test "session-write-check: detects execution of session-written file by basename" {
  _write_trace_entry "/home/user/project/payload.py"
  check_session_written_file "Bash" '{"command":"python3 payload.py"}'
  [ "$SESSION_WRITE_EXEC_MATCHED" = "true" ]
  [ "$SESSION_WRITE_EXEC_FILE" = "/home/user/project/payload.py" ]
}

@test "session-write-check: no match when file was not written this session" {
  check_session_written_file "Bash" '{"command":"bash setup.sh"}'
  [ "$SESSION_WRITE_EXEC_MATCHED" = "false" ]
}

@test "session-write-check: no match for Write tool (only checks Bash)" {
  _write_trace_entry "/home/user/project/test.sh"
  check_session_written_file "Write" '{"file_path":"/home/user/project/test.sh"}'
  [ "$SESSION_WRITE_EXEC_MATCHED" = "false" ]
}

@test "session-write-check: detects Edit-written files too" {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"/home/user/project/edited.sh"},"decision":"allow","file_path":"/home/user/project/edited.sh","timestamp":"2026-01-01T00:00:00Z","session_id":"test-session"}\n' \
    >> "$LANEKEEP_TRACE_FILE"
  check_session_written_file "Bash" '{"command":"bash edited.sh"}'
  [ "$SESSION_WRITE_EXEC_MATCHED" = "true" ]
}

@test "session-write-check: no match when trace file does not exist" {
  rm -f "$LANEKEEP_TRACE_FILE"
  check_session_written_file "Bash" '{"command":"bash exploit.sh"}'
  [ "$SESSION_WRITE_EXEC_MATCHED" = "false" ]
}

@test "session-write-check: handles empty command gracefully" {
  _write_trace_entry "/home/user/project/exploit.sh"
  check_session_written_file "Bash" '{"command":""}'
  [ "$SESSION_WRITE_EXEC_MATCHED" = "false" ]
}

@test "session-write-check: handles missing command field gracefully" {
  _write_trace_entry "/home/user/project/exploit.sh"
  check_session_written_file "Bash" '{}'
  [ "$SESSION_WRITE_EXEC_MATCHED" = "false" ]
}
