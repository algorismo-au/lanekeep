#!/usr/bin/env bats
# XSS and DOM injection rules — validates csec-003 (consolidated).
#
# Covers: innerHTML, dangerouslySetInnerHTML, document.write()

load ../test_helper

setup()    { setup_rules_env; }
teardown() { teardown_rules_env; }

# ============================================================================
# csec-003: innerHTML
# ============================================================================

@test "csec-003: innerHTML via Write triggers ask" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"app.js","content":"el.innerHTML = userInput;"}' || true
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"innerHTML"* ]]
}

@test "csec-003: innerHTML via Edit triggers ask" {
  _isolate_rules "csec-003"
  rules_eval "Edit" '{"file_path":"app.js","old_string":"el.textContent = x","new_string":"el.innerHTML = data;"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "csec-003: innerHTML case-insensitive match" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"app.js","content":"document.getElementById(\"x\").InnerHTML = val;"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "csec-003: innerHTML via Bash is not matched (tool filter)" {
  _isolate_rules "csec-003"
  rules_eval "Bash" '{"command":"echo innerHTML"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "csec-003: textContent is allowed (safe alternative)" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"app.js","content":"el.textContent = userInput;"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# csec-004: dangerouslySetInnerHTML (React) — now consolidated into csec-003
# ============================================================================

@test "csec-004: dangerouslySetInnerHTML via Write triggers ask" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"App.tsx","content":"<div dangerouslySetInnerHTML={{__html: data}} />"}' || true
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"XSS"* ]]
}

@test "csec-004: dangerouslySetInnerHTML via Edit triggers ask" {
  _isolate_rules "csec-003"
  rules_eval "Edit" '{"file_path":"Component.jsx","old_string":"<p>{text}</p>","new_string":"<p dangerouslySetInnerHTML={{__html: text}} />"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "csec-004: dangerouslySetInnerHTML case-insensitive match" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"App.tsx","content":"DANGEROUSLYSETINNERHTML={{__html: x}}"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "csec-004: dangerouslySetInnerHTML via Bash is not matched (tool filter)" {
  _isolate_rules "csec-003"
  rules_eval "Bash" '{"command":"grep dangerouslySetInnerHTML src/"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "csec-004: normal JSX content is allowed" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"App.tsx","content":"<div>{sanitizedContent}</div>"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# csec-005: document.write() — now consolidated into csec-003
# ============================================================================

@test "csec-005: document.write() via Write triggers ask" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"page.html","content":"document.write(userInput);"}' || true
  [ "$RULES_DECISION" = "ask" ]
  [[ "$RULES_REASON" == *"XSS"* ]]
}

@test "csec-005: document.write with string literal via Edit triggers ask" {
  _isolate_rules "csec-003"
  rules_eval "Edit" '{"file_path":"app.js","old_string":"// placeholder","new_string":"document.write(\"<h1>\" + title + \"</h1>\");"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "csec-005: document.write via Bash is not matched (tool filter)" {
  _isolate_rules "csec-003"
  rules_eval "Bash" '{"command":"grep document.write( src/"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "csec-005: document.writeln is not matched (different API)" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"app.js","content":"document.writeln(text);"}'
  [ "$RULES_DECISION" = "allow" ]
}

@test "csec-005: document.createElement is allowed (safe DOM API)" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"app.js","content":"const el = document.createElement(\"div\");"}'
  [ "$RULES_DECISION" = "allow" ]
}

# ============================================================================
# Combined: all three rules active
# ============================================================================

@test "csec-003,004,005: innerHTML triggers with all XSS rules active" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"app.js","content":"el.innerHTML = input;"}' || true
  [ "$RULES_DECISION" = "ask" ]
}

@test "csec-003,004,005: safe DOM code passes all XSS rules" {
  _isolate_rules "csec-003"
  rules_eval "Write" '{"file_path":"app.js","content":"el.textContent = input; const div = document.createElement(\"div\");"}'
  [ "$RULES_DECISION" = "allow" ]
}
