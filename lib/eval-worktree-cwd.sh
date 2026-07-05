#!/usr/bin/env bash
# shellcheck disable=SC2034
# Tier 0.7: cwd == WORKTREE_ROOT invariant (advisory).
#
# Enforces (advisory today, deny in a follow-up rollout) that cwd-sensitive
# tool calls fire with realpath($PWD) == realpath($WORKTREE_ROOT). Catches
# worktree-misconfiguration bugs — e.g. an agent shelled from the parent
# repo running Bash tools that then touch files outside its intended
# blast radius.
#
# WORKTREE_ROOT is expected to be set by the loop runner (shipper) when it
# spawns Claude in a per-task worktree. If unset, the evaluator skips
# entirely — that's the permissive default for non-shipper sessions.
#
# Rollout (per Symphony §9.5): advisory-only for one week — evaluator
# always returns 0 and the handler emits a WARN advisory. Flip the return
# code to 1 (and let the handler promote to BLOCKED) in a follow-up task
# with `deps: [<#4>]`.

WORKTREE_CWD_PASSED=true
WORKTREE_CWD_REASON="Passed"
WORKTREE_CWD_DECISION="warn"

worktree_cwd_eval() {
  local tool_name="$1"
  # tool_input is unused today; keep the two-arg signature so the wire-in
  # matches sibling evaluators and future policy can key off it.
  # shellcheck disable=SC2034
  local tool_input="$2"
  WORKTREE_CWD_PASSED=true
  WORKTREE_CWD_REASON="Passed"

  # Skip if worktree root is not configured (typical for non-shipper sessions).
  [ -n "${WORKTREE_ROOT:-}" ] || return 0

  # Only check cwd-sensitive tools. Read/Grep/Glob take explicit paths; Bash
  # + Write + Edit + NotebookEdit rely on cwd for relative-path resolution.
  case "$tool_name" in
    Bash|Write|Edit|NotebookEdit) ;;
    *) return 0 ;;
  esac

  local expected_pwd actual_pwd
  expected_pwd=$(realpath -m -- "$WORKTREE_ROOT" 2>/dev/null) || expected_pwd="$WORKTREE_ROOT"
  actual_pwd=$(realpath -m -- "$PWD" 2>/dev/null) || actual_pwd="$PWD"

  if [ "$expected_pwd" != "$actual_pwd" ]; then
    WORKTREE_CWD_PASSED=false
    WORKTREE_CWD_REASON="[LaneKeep] ADVISORY: cwd '$actual_pwd' != WORKTREE_ROOT '$expected_pwd' (worktree misconfiguration?)"
  fi
  # Advisory only: always return 0 so the handler emits a WARN but never
  # blocks. Follow-up task (deps:[<#4>]) flips this to `return 1`.
  return 0
}
