#!/usr/bin/env bats
# Git history audit — catches sensitive data committed to this repo.
# Run after every commit: bats tests/hardening/test-git-history-audit.bats
#
# What it checks:
#   AUDIT-01  No real credentials in any production-code diff
#   AUDIT-02  -----BEGIN lines are only intentional public keys in keys/
#   AUDIT-03  api_key values in production code are all variable references
#   AUDIT-04  No .env / credentials / secrets files ever committed
#   AUDIT-05  No internal hostnames or private IP ranges in production code
#   AUDIT-06  Author email list has not grown beyond expected set
#   AUDIT-07  No large unexpected binary files or compiled binaries in history
#
# Scope: checks production code only — test files (tests/, *.bats, fixtures/)
# and rule definitions (defaults/) are excluded from content scans, since those
# intentionally contain fake credential strings to verify detection works.

setup_file() {
  export LANEKEEP_DIR
  LANEKEEP_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  # Full patch log for production code only, written to a temp file once.
  # Excludes: tests/, defaults/ (rule definitions), fixtures/ — these
  # intentionally contain fake credential patterns to verify detection works.
  export PROD_PATCH_LOG="$BATS_FILE_TMPDIR/prod-patch-log.txt"
  git -C "$LANEKEEP_DIR" log -p --all \
    -- ':(exclude)tests/' ':(exclude)defaults/' ':(exclude)fixtures/' ':(exclude)*.bats' \
    > "$PROD_PATCH_LOG"
}

# ---------------------------------------------------------------------------
# AUDIT-01: Real credential patterns must not appear in production diffs
# ---------------------------------------------------------------------------

@test "AUDIT-01: no AWS access key IDs (AKIA…) in production code" {
  # AKIAIOSFODNN7EXAMPLE is the standard AWS docs fake key — intentional in bin/lanekeep-demo
  local hits
  hits=$(grep -E '^\+.*AKIA[0-9A-Z]{16}' "$PROD_PATCH_LOG" \
    | grep -cv 'AKIAIOSFODNN7EXAMPLE' || true)
  [ "$hits" -eq 0 ]
}

@test "AUDIT-01: no OpenAI-style secret keys (sk-…) in production code" {
  local hits
  hits=$(grep -cE '^\+.*\bsk-[A-Za-z0-9]{20,}' "$PROD_PATCH_LOG" || true)
  [ "$hits" -eq 0 ]
}

@test "AUDIT-01: no GitHub PATs (ghp_…) in production code" {
  local hits
  hits=$(grep -cE '^\+.*ghp_[A-Za-z0-9]{36,}' "$PROD_PATCH_LOG" || true)
  [ "$hits" -eq 0 ]
}

@test "AUDIT-01: no GitLab tokens (glpat-…) in production code" {
  local hits
  hits=$(grep -cE '^\+.*glpat-[A-Za-z0-9_-]{20,}' "$PROD_PATCH_LOG" || true)
  [ "$hits" -eq 0 ]
}

@test "AUDIT-01: no hardcoded password assignments in production code" {
  # Matches: password=<literal> — excludes shell variable refs and template placeholders
  local hits
  hits=$(grep -E '^\+.*(password|passwd)\s*=\s*[^$\{<"'"'"'\s\\]' "$PROD_PATCH_LOG" \
    | grep -civE '(env|getenv|environ|variable|config_key|field|param|your|example|placeholder|description|string|match)' \
    || true)
  [ "$hits" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AUDIT-02: -----BEGIN lines must only be intentional public keys in keys/
# ---------------------------------------------------------------------------

@test "AUDIT-02: no -----BEGIN PRIVATE KEY lines in production code" {
  # Production code should never add a private key. Public keys in keys/ are fine.
  local hits
  hits=$(grep -cE '^\+.*-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY' "$PROD_PATCH_LOG" || true)
  [ "$hits" -eq 0 ]
}

@test "AUDIT-02: no private key files ever added to the repo" {
  local hits
  hits=$(git -C "$LANEKEEP_DIR" log --all --diff-filter=A --name-only --format="" \
    | grep -cE '\.(pem|key|p12|pfx|jks)$' || true)
  [ "$hits" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AUDIT-03: api_key values in production code must be variable references
# ---------------------------------------------------------------------------

@test "AUDIT-03: every api_key in production code is a variable reference or placeholder" {
  local hits
  hits=$(grep -E '^\+.*api_key[_"]?\s*[:=]\s*' "$PROD_PATCH_LOG" \
    | grep -civE '(\$\{|\$[A-Z_a-z]|local api_key|ANTHROPIC_API_KEY|<your|placeholder|env:|your[-_]key|description|field|config)' \
    || true)
  [ "$hits" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AUDIT-04: Credential/env files never committed
# ---------------------------------------------------------------------------

@test "AUDIT-04: no .env files ever committed" {
  local hits
  hits=$(git -C "$LANEKEEP_DIR" log --all --diff-filter=A --name-only --format="" \
    | grep -cE '(^|/)\.env($|\.)' || true)
  [ "$hits" -eq 0 ]
}

@test "AUDIT-04: no credentials or secrets files ever committed" {
  local hits
  hits=$(git -C "$LANEKEEP_DIR" log --all --diff-filter=A --name-only --format="" \
    | grep -ciE '(^|/)(credentials|secrets|\.secret|auth\.json|service.account)' || true)
  [ "$hits" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AUDIT-05: No internal hostnames or RFC-1918 IPs in production code
# ---------------------------------------------------------------------------

@test "AUDIT-05: no RFC-1918 IP addresses hardcoded in production code" {
  local hits
  hits=$(grep -E '^\+.*(192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)' \
    "$PROD_PATCH_LOG" | grep -cv '#' || true)
  [ "$hits" -eq 0 ]
}

@test "AUDIT-05: no .internal or .corp hostnames in production code" {
  local hits
  hits=$(grep -cE '^\+.*\b[a-z0-9-]+\.(internal|corp|intranet)\b' "$PROD_PATCH_LOG" || true)
  [ "$hits" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AUDIT-06: Author list has not grown beyond expected committers
# ---------------------------------------------------------------------------

@test "AUDIT-06: only expected authors in git history" {
  # Update this list when adding a new legitimate contributor
  local -a allowed_emails=(
    "moabbas.tech@gmail.com"
    "noreply@anthropic.com"
    "49699333+dependabot[bot]@users.noreply.github.com"
  )

  local unexpected=0
  while IFS= read -r email; do
    local found=false
    for allowed in "${allowed_emails[@]}"; do
      [[ "$email" == "$allowed" ]] && found=true && break
    done
    if [ "$found" = false ]; then
      echo "Unexpected author email in git history: $email" >&2
      unexpected=1
    fi
  done < <(git -C "$LANEKEEP_DIR" log --format="%ae" --all | sort -u)
  [ "$unexpected" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AUDIT-07: No unexpected large binaries or compiled executables in history
# ---------------------------------------------------------------------------

@test "AUDIT-07: no unexpected blobs over 5 MB in history" {
  local -a allowed_large=(
    "ui/js/mermaid.min.js"
  )
  local threshold=$((5 * 1024 * 1024))
  local unexpected=0

  while IFS=' ' read -r type oid size rest; do
    [ "$type" = "blob" ] || continue
    [ "$size" -gt "$threshold" ] || continue
    local name="$rest"
    local found=false
    for allowed in "${allowed_large[@]}"; do
      [[ "$name" == "$allowed" ]] && found=true && break
    done
    if [ "$found" = false ]; then
      echo "Large unexpected blob: $name ($size bytes)" >&2
      unexpected=1
    fi
  done < <(git -C "$LANEKEEP_DIR" rev-list --objects --all \
    | git -C "$LANEKEEP_DIR" cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)')
  [ "$unexpected" -eq 0 ]
}

@test "AUDIT-07: no ELF/Mach-O/PE binaries ever committed" {
  local unexpected=0
  while IFS=' ' read -r type oid; do
    [ "$type" = "blob" ] || continue
    local magic
    magic=$(git -C "$LANEKEEP_DIR" cat-file blob "$oid" 2>/dev/null \
      | head -c 4 | xxd -p 2>/dev/null || true)
    case "$magic" in
      7f454c46)        echo "ELF binary: $oid" >&2;    unexpected=1 ;;
      feedface|feedfacf|cefaedfe|cffaedfe)
                       echo "Mach-O binary: $oid" >&2; unexpected=1 ;;
      4d5a9000)        echo "PE binary: $oid" >&2;     unexpected=1 ;;
    esac
  done < <(git -C "$LANEKEEP_DIR" rev-list --objects --all \
    | git -C "$LANEKEEP_DIR" cat-file --batch-check='%(objecttype) %(objectname)')
  [ "$unexpected" -eq 0 ]
}
