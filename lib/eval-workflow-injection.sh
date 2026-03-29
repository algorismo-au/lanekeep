#!/usr/bin/env bash
# shellcheck disable=SC2034  # WORKFLOW_INJECT_* globals set here, read externally via indirection
# Tier 2.5: GitHub Actions workflow expression injection detector
#
# Detects ${{ github.event.* }} used directly in run: steps — a well-known
# command injection vector where untrusted input (issue titles, PR bodies,
# commit messages) is interpolated into shell execution contexts.
#
# Safe pattern:  assign to env: first, reference $VAR in run:
# Unsafe pattern: echo "${{ github.event.issue.title }}" in run:
#
# References: CWE-78, GHSA workflow-injection

WORKFLOW_INJECT_PASSED=true
WORKFLOW_INJECT_REASON="Passed"
WORKFLOW_INJECT_DECISION="ask"

# Attacker-controlled GitHub Actions context variables
_WI_UNTRUSTED_SOURCES=(
  "github.event.issue.title"
  "github.event.issue.body"
  "github.event.pull_request.title"
  "github.event.pull_request.body"
  "github.event.pull_request.head.ref"
  "github.event.pull_request.head.label"
  "github.event.pull_request.head.repo.default_branch"
  "github.event.comment.body"
  "github.event.review.body"
  "github.event.review_comment.body"
  "github.event.pages.*.page_name"
  "github.event.commits.*.message"
  "github.event.commits.*.author.email"
  "github.event.commits.*.author.name"
  "github.event.head_commit.message"
  "github.event.head_commit.author.email"
  "github.event.head_commit.author.name"
  "github.head_ref"
)

workflow_inject_eval() {
  local tool_name="$1"
  local tool_input="$2"
  WORKFLOW_INJECT_PASSED=true
  WORKFLOW_INJECT_REASON="Passed"
  WORKFLOW_INJECT_DECISION="ask"

  # Only applies to Write and Edit
  case "$tool_name" in
    Write|Edit) ;;
    *) return 0 ;;
  esac

  # Extract file path
  local file_path
  file_path=$(printf '%s' "$tool_input" | jq -r '.file_path // ""' 2>/dev/null) || return 0
  [ -n "$file_path" ] || return 0

  # Only applies to GitHub Actions workflow files
  if ! printf '%s' "$file_path" | grep -qiE '\.github/(workflows|actions)/[^/]+\.ya?ml$'; then
    return 0
  fi

  # Check if evaluator is enabled (default: true)
  local is_enabled
  is_enabled=$(jq -r '.evaluators.workflow_injection.enabled // true' \
    "${LANEKEEP_CONFIG_FILE:-/dev/null}" 2>/dev/null) || is_enabled="true"
  [ "$is_enabled" != "false" ] || return 0

  # Extract the content being written
  local content
  case "$tool_name" in
    Write) content=$(printf '%s' "$tool_input" | jq -r '.content // ""' 2>/dev/null) ;;
    Edit)  content=$(printf '%s' "$tool_input" | jq -r '.new_string // ""' 2>/dev/null) ;;
  esac
  [ -n "$content" ] || return 0

  # State-machine YAML scanner: detect ${{ <source> }} in run: context (not env:)
  #
  # Tracks indent levels of run: and env: blocks. Flags any untrusted expression
  # in a run: continuation that is NOT inside an env: block (where it is safe).
  # Also catches inline values on the run: line itself.
  local unsafe_line=""
  local unsafe_source=""

  local src
  for src in "${_WI_UNTRUSTED_SOURCES[@]}"; do
    # Build awk regex: escape dots, replace glob * with [^}]*
    local awk_pat
    awk_pat=$(printf '%s' "$src" | sed 's/\./\\./g; s/\*/[^}]*/g')

    local scan_result
    scan_result=$(printf '%s' "$content" | awk -v pat="$awk_pat" '
      BEGIN {
        in_run = 0; run_indent = -1
        in_env = 0; env_indent = -1
        hit = ""
      }
      {
        line = $0
        # Compute leading spaces (indent level)
        n = split(line, chars, "")
        indent = 0
        for (i = 1; i <= n; i++) {
          if (chars[i] == " ") indent++
          else break
        }

        # Skip blank lines — do not affect context tracking
        if (line ~ /^[[:space:]]*$/) next

        # run: key detected
        if (line ~ /^[[:space:]]*run:/) {
          # Measure indent of the key itself
          key_indent = indent
          run_indent = key_indent
          in_run = 1
          in_env = 0; env_indent = -1
          # Check inline value: run: echo "${{ github.event... }}"
          if (line ~ ("\\$\\{\\{[^}]*" pat)) {
            hit = line; exit
          }
          next
        }

        # env: key detected — safe context for assigning expressions
        if (line ~ /^[[:space:]]*env:/) {
          key_indent = indent
          env_indent = key_indent
          in_env = 1
          in_run = 0; run_indent = -1
          next
        }

        # Dedent back to or past a context key exits that context
        if (in_run && run_indent >= 0 && indent <= run_indent) {
          in_run = 0; run_indent = -1
        }
        if (in_env && env_indent >= 0 && indent <= env_indent) {
          in_env = 0; env_indent = -1
        }

        # Flag: untrusted expression in run: continuation (env: is safe)
        if (in_run && !in_env && line ~ ("\\$\\{\\{[^}]*" pat)) {
          hit = line; exit
        }
      }
      END { print hit }
    ')

    if [ -n "$scan_result" ]; then
      unsafe_line="$scan_result"
      unsafe_source="$src"
      break
    fi
  done

  if [ -n "$unsafe_line" ]; then
    local trimmed
    trimmed=$(printf '%s' "$unsafe_line" | sed 's/^[[:space:]]*//' | head -c 200)
    WORKFLOW_INJECT_PASSED=false
    WORKFLOW_INJECT_DECISION="ask"
    WORKFLOW_INJECT_REASON="[LaneKeep] NEEDS APPROVAL — WorkflowInjectionEvaluator (Tier 2.5)
Unsafe GitHub Actions expression injection detected in: $file_path

  Matched: $trimmed
  Source:  \${{ $unsafe_source }}

Attacker-controlled input interpolated directly into a run: step enables
command injection via crafted issues, PRs, or commit messages.

Safe pattern:
  env:
    VALUE: \${{ $unsafe_source }}
  run: echo \"\$VALUE\"

Compliance: CWE-78 (OS Command Injection)"
    return 1
  fi

  return 0
}
