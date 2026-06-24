#!/usr/bin/env bash
# Ed25519 config/rule signature verification via openssl pkeyutl
# Returns: 0 = valid, 1 = invalid/tampered, 2 = unsigned or no tools/pubkey

verify_inline_sig() {
  local json_content="$1"
  local pubkey_pem="$2"

  # Bail if openssl not available — warn once per process so operators know
  # verification is being skipped (guard prevents spam in pack-import loops)
  if ! command -v openssl >/dev/null 2>&1; then
    if [ -z "${LANEKEEP_OPENSSL_WARNED:-}" ]; then
      echo "[lanekeep] WARNING: openssl not found on PATH — signature verification skipped" >&2
      LANEKEEP_OPENSSL_WARNED=1
    fi
    return 2
  fi

  # Bail if no pubkey
  [ -n "$pubkey_pem" ] && [ -f "$pubkey_pem" ] || return 2

  # Extract signature from JSON (base64-encoded)
  local signature
  signature=$(printf '%s' "$json_content" | jq -r '._signature // empty' 2>/dev/null) || return 2
  [ -n "$signature" ] || return 2

  # Strip _signature field to get canonical content for verification
  local canonical
  canonical=$(printf '%s' "$json_content" | jq -c 'del(._signature)' 2>/dev/null) || return 1

  # Hash the canonical JSON with SHA-256
  local hash_file sig_file
  hash_file=$(umask 077 && mktemp "${TMPDIR:-/tmp}/lanekeep-XXXXXX")
  sig_file=$(umask 077 && mktemp "${TMPDIR:-/tmp}/lanekeep-XXXXXX")
  # shellcheck disable=SC2064  # early expansion intentional: captures temp paths at set-time for safe RETURN cleanup under set -u
  trap "rm -f '$hash_file' '$sig_file'" RETURN

  printf '%s' "$canonical" | sha256sum | cut -d' ' -f1 | tr -d '\n' > "$hash_file"

  # Decode base64 signature
  printf '%s' "$signature" | base64 -d > "$sig_file" 2>/dev/null || { rm -f "$hash_file" "$sig_file"; return 1; }

  # Verify with openssl pkeyutl (Ed25519)
  if openssl pkeyutl -verify -pubin -inkey "$pubkey_pem" \
      -sigfile "$sig_file" -in "$hash_file" -rawin >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}
