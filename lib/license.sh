#!/usr/bin/env bash
# License tier resolution — stub for community release
# Real license validation will be added in a future release.

LANEKEEP_API_VERSION=1
export LANEKEEP_API_VERSION

resolve_license_tier() {
  # Currently: environment variable only (default: community)
  # Future: read from ~/.config/lanekeep/license.jwt, validate Ed25519 signature
  LANEKEEP_LICENSE_TIER="${LANEKEEP_LICENSE_TIER:-community}"
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
