#!/usr/bin/env bash
# Unit tests for lib/eval-worktree-cwd.sh (Phase 1 #4).
# Plain-bash suite (matches `test-*.sh` convention in the plan's #4 spec).
#
# Contract:
#   - WORKTREE_ROOT unset            → pass (skip)
#   - $PWD == $WORKTREE_ROOT         → pass
#   - $PWD != $WORKTREE_ROOT         → advisory-only fail (PASSED=false),
#                                       but function still returns 0 for the
#                                       initial rollout
#   - Read/Grep/Glob calls           → pass (cwd-insensitive)
#   - Bash/Write/Edit/NotebookEdit   → checked
#
# Flip to enforcement in a follow-up commit (return 1 on mismatch); add a
# `enforce_returns_one` case here at the same time.

set -uo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
EVAL="$ROOT/lib/eval-worktree-cwd.sh"
RESULTS=$(mktemp -t worktree-cwd-results-XXXX)
trap 'rm -f "$RESULTS"' EXIT

# Each case runs in a subshell to keep env state isolated. Subshells can't
# mutate PASS/FAIL counters directly, so results funnel through $RESULTS.
_record() { printf '%s\n' "$1" >> "$RESULTS"; }
pass_sub() { _record "PASS: $1"; printf '  PASS  %s\n' "$1"; }
fail_sub() { _record "FAIL: $1"; printf '  FAIL  %s\n' "$1" >&2; }

expect_pass_true() {
  local desc="$1" rc="$2"
  # WORKTREE_CWD_PASSED expected to have been set by the eval call in the
  # subshell before this is invoked.
  if [ "$rc" -eq 0 ] && [ "${WORKTREE_CWD_PASSED:-}" = "true" ]; then
    pass_sub "$desc"
  else
    fail_sub "$desc — rc=$rc passed=${WORKTREE_CWD_PASSED:-?} reason=${WORKTREE_CWD_REASON:-?}"
  fi
}

expect_pass_false_advisory() {
  local desc="$1" rc="$2"
  if [ "$rc" -eq 0 ] && [ "${WORKTREE_CWD_PASSED:-}" = "false" ]; then
    pass_sub "$desc"
  else
    fail_sub "$desc — rc=$rc passed=${WORKTREE_CWD_PASSED:-?} reason=${WORKTREE_CWD_REASON:-?}"
  fi
}

echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$EVAL"; then
    pass_sub "shellcheck clean on eval-worktree-cwd.sh"
  else
    fail_sub "shellcheck reported issues on eval-worktree-cwd.sh"
  fi
else
  echo "  SKIP  shellcheck not installed"
fi

echo "== behaviour =="

# 1. WORKTREE_ROOT unset → skip cleanly (pass)
(
  # shellcheck source=/dev/null
  source "$EVAL"
  unset WORKTREE_ROOT
  worktree_cwd_eval "Bash" '{"command":"ls"}'
  expect_pass_true "WORKTREE_ROOT unset → skip (pass)" "$?"
)

# 2. cwd == WORKTREE_ROOT → pass
(
  # shellcheck source=/dev/null
  source "$EVAL"
  TMP=$(mktemp -d)
  cd "$TMP" || exit 1
  export WORKTREE_ROOT="$TMP"
  worktree_cwd_eval "Bash" '{"command":"ls"}'
  expect_pass_true "cwd matches WORKTREE_ROOT → pass" "$?"
  rm -rf "$TMP"
)

# 3. cwd != WORKTREE_ROOT + Bash → advisory fail (passed=false, rc=0)
(
  # shellcheck source=/dev/null
  source "$EVAL"
  A=$(mktemp -d); B=$(mktemp -d)
  cd "$A" || exit 1
  export WORKTREE_ROOT="$B"
  worktree_cwd_eval "Bash" '{"command":"ls"}'
  expect_pass_false_advisory "Bash + cwd mismatch → advisory fail" "$?"
  rm -rf "$A" "$B"
)

# 4. cwd != WORKTREE_ROOT + Read → skip (cwd-insensitive)
(
  # shellcheck source=/dev/null
  source "$EVAL"
  A=$(mktemp -d); B=$(mktemp -d)
  cd "$A" || exit 1
  export WORKTREE_ROOT="$B"
  worktree_cwd_eval "Read" '{"file_path":"/tmp/x"}'
  expect_pass_true "Read tool → cwd-insensitive skip" "$?"
  rm -rf "$A" "$B"
)

# 5. cwd != WORKTREE_ROOT + Write → advisory fail (cwd-sensitive)
(
  # shellcheck source=/dev/null
  source "$EVAL"
  A=$(mktemp -d); B=$(mktemp -d)
  cd "$A" || exit 1
  export WORKTREE_ROOT="$B"
  worktree_cwd_eval "Write" '{"file_path":"x.txt","content":""}'
  expect_pass_false_advisory "Write + cwd mismatch → advisory fail" "$?"
  rm -rf "$A" "$B"
)

# 6. Reason string names both anchors on mismatch (triage clarity)
(
  # shellcheck source=/dev/null
  source "$EVAL"
  A=$(mktemp -d); B=$(mktemp -d)
  cd "$A" || exit 1
  export WORKTREE_ROOT="$B"
  worktree_cwd_eval "Bash" '{"command":"ls"}'
  case "$WORKTREE_CWD_REASON" in
    *ADVISORY*cwd*WORKTREE_ROOT*)
      pass_sub "reason string names both cwd and WORKTREE_ROOT" ;;
    *)
      fail_sub "reason string missing anchors: $WORKTREE_CWD_REASON" ;;
  esac
  rm -rf "$A" "$B"
)

echo ""
echo "==============================="
P=$(grep -c '^PASS:' "$RESULTS" || true)
F=$(grep -c '^FAIL:' "$RESULTS" || true)
echo "PASS: $P   FAIL: $F"
[ "$F" -eq 0 ]
