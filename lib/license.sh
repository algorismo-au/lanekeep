#!/usr/bin/env bash
# License tier resolution — Ed25519-verified key file, with env var override.

LANEKEEP_API_VERSION=1
export LANEKEEP_API_VERSION

# Verify an Ed25519-signed license key file and print the tier on success.
# Key file format: JSON with tier, issued_to, expires_utc, _signature fields.
# The _signature covers del(._signature) on the canonical JSON (same convention
# as pack signing in signing.sh).
#
# Usage: verify_license_key [key_file [pubkey_pem]]
# Returns: 0 and prints tier on success; non-zero on failure.
verify_license_key() {
  local key_file="${1:-${HOME}/.config/lanekeep/license.key}"
  local pubkey_pem="${2:-${LANEKEEP_DIR:-}/keys/license-signing.pub}"

  [ -f "$key_file" ] || return 1
  [ -f "$pubkey_pem" ] || return 1

  # Source signing module if not already loaded
  if ! declare -f verify_inline_sig >/dev/null 2>&1; then
    local signing_sh="${LANEKEEP_DIR:-}/lib/signing.sh"
    [ -f "$signing_sh" ] || return 1
    # shellcheck source=/dev/null
    source "$signing_sh"
  fi

  local content
  content=$(cat "$key_file" 2>/dev/null) || return 1

  # Validate JSON and extract tier
  local tier
  tier=$(printf '%s' "$content" | jq -r '.tier // empty' 2>/dev/null) || return 1
  [ -n "$tier" ] || return 1

  # Validate tier value
  case "$tier" in
    community|pro|enterprise) ;;
    *) return 1 ;;
  esac

  # Check expiry (wall clock only — no network)
  local expires
  expires=$(printf '%s' "$content" | jq -r '.expires_utc // empty' 2>/dev/null)
  if [ -n "$expires" ]; then
    local now_epoch=0 exp_epoch=0
    now_epoch=$(date -u +%s 2>/dev/null) || now_epoch=0
    # GNU date (Linux): date -u -d; BSD date (macOS): date -u -j -f
    exp_epoch=$(date -u -d "$expires" +%s 2>/dev/null) || \
      exp_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$expires" +%s 2>/dev/null) || \
      exp_epoch=0
    if [ "$exp_epoch" -gt 0 ] && [ "$now_epoch" -gt "$exp_epoch" ]; then
      echo "[LaneKeep] WARNING: License key expired ($expires) — falling back to community tier" >&2
      return 1
    fi
  fi

  # Verify Ed25519 signature
  verify_inline_sig "$content" "$pubkey_pem" || return 1

  printf '%s' "$tier"
  return 0
}

resolve_license_tier() {
  # 1. Explicit env var takes precedence (CI, testing, backward compat)
  if [ -n "${LANEKEEP_LICENSE_TIER:-}" ]; then
    export LANEKEEP_LICENSE_TIER
    return 0
  fi

  # 2. Try Ed25519-verified license key file (no network)
  local _verified_tier
  _verified_tier=$(verify_license_key 2>/dev/null) && {
    LANEKEEP_LICENSE_TIER="$_verified_tier"
    export LANEKEEP_LICENSE_TIER
    return 0
  }

  # 3. Default: community
  LANEKEEP_LICENSE_TIER="community"
  export LANEKEEP_LICENSE_TIER
}

print_license_info() {
  resolve_license_tier
  echo "LaneKeep License Information"
  echo "======================"
  echo ""
  echo "  Tier:        $LANEKEEP_LICENSE_TIER"
  echo "  API version: $LANEKEEP_API_VERSION"
  echo "  Status:      active"
  echo ""
  case "$LANEKEEP_LICENSE_TIER" in
    community)
      echo "  All community features enabled."
      echo "  Upgrade to Pro for centralized policies, compliance packs, and audit reports."
      ;;
    pro)
      echo "  Pro features enabled: compliance packs, team policy sync, audit reports."
      ;;
    enterprise)
      echo "  Enterprise features enabled: all Pro features plus SSO, RBAC, dashboard."
      ;;
  esac
}
