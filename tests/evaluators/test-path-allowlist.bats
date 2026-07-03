#!/usr/bin/env bats
# Tests for evaluators.<key>.path_allowlist in input_pii + result_transform.
# Suppresses false positives on conventional documentation files (SECURITY.md
# vuln-reporting emails, CONTRIBUTING.md sample tokens, etc.) that legitimately
# contain content matching PII/secret patterns.

setup() {
  export LANEKEEP_DIR="$BATS_TEST_DIRNAME/../.."
  source "$BATS_TEST_DIRNAME/../../lib/config.sh"
  source "$BATS_TEST_DIRNAME/../../lib/eval-input-pii.sh"
  source "$BATS_TEST_DIRNAME/../../lib/eval-result-transform.sh"

  TEST_TMP="$(mktemp -d)"
  export LANEKEEP_CONFIG_FILE="$TEST_TMP/lanekeep.json"

  cat > "$LANEKEEP_CONFIG_FILE" <<'EOF'
{
  "evaluators": {
    "input_pii": {
      "enabled": true,
      "on_detect": "ask",
      "tools": ["Write", "Edit"],
      "path_allowlist": [
        "(^|/)SECURITY\\.md$",
        "(^|/)CONTRIBUTING\\.md$"
      ],
      "pii_patterns": [
        "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
      ],
      "pii_allowlist": [],
      "compliance_by_category": { "pii": [] }
    },
    "result_transform": {
      "enabled": true,
      "on_detect": "redact",
      "path_allowlist": [
        "(^|/)SECURITY\\.md$",
        "(^|/)CONTRIBUTING\\.md$"
      ],
      "secret_patterns": ["AKIA[0-9A-Z]{16}"],
      "injection_patterns": [],
      "hidden_char_patterns": [],
      "css_hiding_patterns": [],
      "html_comment_injection_patterns": [],
      "compliance_by_category": { "secret": [] },
      "max_result_bytes": 1048576,
      "truncate_at": 524288,
      "tools": []
    }
  }
}
EOF
}

teardown() {
  rm -rf "$TEST_TMP" ; return 0
}

# ============================================================
# input_pii: path_allowlist
# ============================================================

@test "input_pii skips Write to SECURITY.md (path allowlisted)" {
  local input='{"file_path":"SECURITY.md","content":"Report vulnerabilities to security@example.com"}'
  input_pii_eval "Write" "$input"
  [ "$INPUT_PII_PASSED" = true ]
  [[ "$INPUT_PII_REASON" == *"allowlisted"* ]]
}

@test "input_pii skips Edit of SECURITY.md at nested path" {
  local input='{"file_path":"project/SECURITY.md","new_string":"Contact: admin@algorismo.com"}'
  input_pii_eval "Edit" "$input"
  [ "$INPUT_PII_PASSED" = true ]
}

@test "input_pii skips Write to CONTRIBUTING.md" {
  local input='{"file_path":"CONTRIBUTING.md","content":"Email maintainers at ops@example.com"}'
  input_pii_eval "Write" "$input"
  [ "$INPUT_PII_PASSED" = true ]
}

@test "input_pii still flags email in non-allowlisted file" {
  local input='{"file_path":"user_data.txt","content":"user email: admin@example.com"}'
  input_pii_eval "Write" "$input" || true
  [ "$INPUT_PII_PASSED" = false ]
}

@test "input_pii path_allowlist is regex-anchored (SECURITYdotmd substring does not match)" {
  # Path 'notes/MySECURITY.mdext' contains 'SECURITY.md' as substring but the
  # anchored (^|/)SECURITY\.md$ pattern must not match it.
  local input='{"file_path":"notes/MySECURITY.mdext","content":"leak@example.com"}'
  input_pii_eval "Write" "$input" || true
  [ "$INPUT_PII_PASSED" = false ]
}

# ============================================================
# result_transform: path_allowlist
# ============================================================

@test "result_transform skips Read of SECURITY.md" {
  # tool_result contains a secret-shaped string; without allowlist this would fire.
  local input='{"file_path":"SECURITY.md"}'
  result_transform_eval "Read" "Contact for AKIAIOSFODNN7EXAMPLE issues" "$input"
  [ "$RESULT_TRANSFORM_PASSED" = true ]
  [[ "$RESULT_TRANSFORM_REASON" == *"allowlisted"* ]]
}

@test "result_transform still redacts secrets in non-allowlisted file" {
  local input='{"file_path":"src/config.ts"}'
  result_transform_eval "Read" "AWS_KEY=AKIAIOSFODNN7EXAMPLE" "$input" || true
  # Not skipped — a detection occurred
  [[ "$RESULT_TRANSFORM_REASON" != *"allowlisted"* ]]
}

@test "result_transform works without tool_input (backwards compatible)" {
  # Two-arg call path used by existing tests must still function.
  result_transform_eval "Bash" "clean output"
  [ "$RESULT_TRANSFORM_PASSED" = true ]
}
