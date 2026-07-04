#!/usr/bin/env bash
# Unit tests for hooks/stop.sh — fixer session-end summary block (Phase 1 #6).
#
# Contract:
#   - fixer missing         → stop.sh exits 0 with no extra output
#   - fixer prints empty    → stop.sh does not emit a fixer line
#   - fixer prints a line   → stop.sh forwards it prefixed "[fixer] "
#   - fixer hangs > 500ms   → stop.sh doesn't hang; caller-side timeout kicks in

set -uo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
STOP="$ROOT/hooks/stop.sh"
RESULTS=$(mktemp -t stop-fixer-results-XXXX)
trap 'rm -f "$RESULTS"' EXIT

pass_sub() { printf 'PASS: %s\n' "$1" >> "$RESULTS"; printf '  PASS  %s\n' "$1"; }
fail_sub() { printf 'FAIL: %s\n' "$1" >> "$RESULTS"; printf '  FAIL  %s\n' "$1" >&2; }

# Run stop.sh inside a subshell with a controlled PATH and env. We suppress
# the notification path by unsetting DISPLAY and pretending notify-send is
# absent; the stderr fallback still emits the SUMMARY line, which is fine —
# the test only asserts on the [fixer] line.
_run_stop_with_stub() {
  local stub_body="$1" outfile="$2"
  local D
  D=$(mktemp -d)
  export PATH_ORIG="$PATH"

  # Baseline fake project so _resolve_project_root doesn't drift.
  mkdir -p "$D/.lanekeep"
  printf '{"action_count":0,"start_epoch":%s}\n' "$(($(date +%s) - 60))" \
    > "$D/.lanekeep/state.json"

  if [ -n "$stub_body" ]; then
    printf '%s' "$stub_body" > "$D/fixer"
    chmod +x "$D/fixer"
    export PATH="$D:$PATH"
  fi

  cd "$D" || return 1
  # `cat >/dev/null` in stop.sh reads stdin; feed empty.
  : | LANEKEEP_STATE_FILE="$D/.lanekeep/state.json" \
      PROJECT_DIR="$D" \
      bash "$STOP" 2> "$outfile"
  local rc=$?

  cd / || true
  export PATH="$PATH_ORIG"
  rm -rf "$D"
  return "$rc"
}

echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$STOP"; then
    pass_sub "shellcheck clean on stop.sh"
  else
    fail_sub "shellcheck reported issues on stop.sh"
  fi
else
  echo "  SKIP  shellcheck not installed"
fi

echo "== behaviour =="

# 1. fixer missing → stop exits 0, no [fixer] line
OUT=$(mktemp)
_run_stop_with_stub "" "$OUT"
rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '\[fixer\]' "$OUT"; then
  pass_sub "fixer missing → no [fixer] line, rc=0"
else
  fail_sub "fixer missing → rc=$rc, stderr: $(head -c 200 "$OUT")"
fi
rm -f "$OUT"

# 2. fixer returns empty → no [fixer] line printed
OUT=$(mktemp)
_run_stop_with_stub $'#!/usr/bin/env bash\nexit 0\n' "$OUT"
rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '\[fixer\]' "$OUT"; then
  pass_sub "fixer prints empty → no [fixer] line"
else
  fail_sub "fixer empty → rc=$rc, stderr: $(head -c 200 "$OUT")"
fi
rm -f "$OUT"

# 3. fixer returns a line → forwarded with [fixer] prefix
OUT=$(mktemp)
_run_stop_with_stub $'#!/usr/bin/env bash\necho "deferred this session: 3 captured"\n' "$OUT"
rc=$?
if [ "$rc" -eq 0 ] && grep -q '^\[fixer\] deferred this session: 3 captured' "$OUT"; then
  pass_sub "fixer prints line → forwarded with [fixer] prefix"
else
  fail_sub "fixer line not forwarded — rc=$rc, stderr: $(head -c 200 "$OUT")"
fi
rm -f "$OUT"

# 4. fixer hangs → stop.sh doesn't hang; overall runs in < 5s
OUT=$(mktemp)
start_epoch=$(date +%s)
_run_stop_with_stub $'#!/usr/bin/env bash\nsleep 60\n' "$OUT"
rc=$?
end_epoch=$(date +%s)
elapsed=$((end_epoch - start_epoch))
# 500ms fixer cap + minor stop.sh overhead → well under 5s
if [ "$rc" -eq 0 ] && [ "$elapsed" -lt 5 ]; then
  pass_sub "hung fixer → stop.sh returns in <5s (${elapsed}s), rc=0"
else
  fail_sub "hung fixer — rc=$rc, elapsed=${elapsed}s"
fi
rm -f "$OUT"

echo ""
echo "==============================="
P=$(grep -c '^PASS:' "$RESULTS" || true)
F=$(grep -c '^FAIL:' "$RESULTS" || true)
echo "PASS: $P   FAIL: $F"
[ "$F" -eq 0 ]
