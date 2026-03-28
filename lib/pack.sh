#!/usr/bin/env bash
# pack.sh — Community pack download and local store management
#
# Local store: ~/.local/share/lanekeep/community/<pack-name>/
# Each entry is a git clone of the pack's repository.
# pack.json at the clone root is the required manifest.
#
# Pack manifest (pack.json) required fields:
#   name        — pack identifier, must match rule ID prefix (e.g. "community-aws")
#   version     — semver string
#   rules_file  — path to rules JSON relative to pack root (default: rules.json)
#   description — human-readable description
#
# Rule ID namespace convention:
#   All rule IDs in a community pack must be prefixed with "<pack-name>-"
#   (e.g. community-aws-001). This allows clean uninstall by prefix.

LANEKEEP_COMMUNITY_DIR="${LANEKEEP_COMMUNITY_DIR:-${HOME}/.local/share/lanekeep/community}"

# Parse a pack ref into URL and optional version tag.
# Format: <git-url>[@<version>]
# Sets PACK_URL and PACK_VERSION in caller's scope.
# Version is only extracted if the part after the last @ contains no / or :
# (to avoid treating git@host: as a version).
pack_parse_ref() {
  local ref="$1"
  local after_at
  after_at="${ref##*@}"
  PACK_URL="$ref"
  PACK_VERSION=""
  if [ "$after_at" != "$ref" ]; then
    case "$after_at" in
      */* | *:*) ;;  # part of the URL itself (git@host: or path component)
      *) PACK_URL="${ref%@*}"; PACK_VERSION="$after_at" ;;
    esac
  fi
}

# Derive a pack name from a git URL.
# Takes the last path segment, strips .git suffix.
# e.g. https://github.com/org/community-aws.git → community-aws
pack_name_from_url() {
  local url="$1"
  local name
  name="${url##*/}"
  name="${name%.git}"
  printf '%s' "$name"
}

# Return the local store directory for a pack.
pack_local_dir() {
  local pack_name="$1"
  printf '%s/%s' "$LANEKEEP_COMMUNITY_DIR" "$pack_name"
}

# Clone a pack into the local store.
# If version is non-empty, checks out that tag/branch after cloning.
pack_clone() {
  local url="$1" version="$2" local_dir="$3"
  mkdir -p "$(dirname "$local_dir")"
  if [ -n "$version" ]; then
    git clone --depth 1 --branch "$version" -- "$url" "$local_dir"
  else
    git clone --depth 1 -- "$url" "$local_dir"
  fi
}

# Pull the latest changes in an existing clone.
# Fetches and resets to origin HEAD (preserves the checked-out branch/tag).
pack_pull() {
  local local_dir="$1"
  git -C "$local_dir" fetch --depth 1
  git -C "$local_dir" reset --hard FETCH_HEAD
}

# Remove the local store directory for a pack.
pack_remove_local() {
  local local_dir="$1"
  [ -d "$local_dir" ] || return 0
  rm -rf "$local_dir"
}

# Validate a cloned pack directory.
# Checks: pack.json exists with required fields, rules file exists with valid schema,
# and all rule IDs use the pack-name prefix.
# Exits non-zero with a message on failure.
pack_validate() {
  local local_dir="$1" pack_name="$2"

  if [ ! -f "$local_dir/pack.json" ]; then
    echo "Error: pack.json not found in $local_dir" >&2
    return 1
  fi

  # Required manifest fields
  local name version
  name=$(jq -r '.name // empty' "$local_dir/pack.json" 2>/dev/null)
  version=$(jq -r '.version // empty' "$local_dir/pack.json" 2>/dev/null)
  if [ -z "$name" ] || [ -z "$version" ]; then
    echo "Error: pack.json missing required fields: name, version" >&2
    return 1
  fi

  # Rules file must exist
  local rules_file
  rules_file=$(pack_rules_file "$local_dir")
  if [ ! -f "$rules_file" ]; then
    echo "Error: rules file not found: $rules_file" >&2
    return 1
  fi

  # Rules file must be valid JSON with a .rules array
  if ! jq -e '.rules | type == "array"' "$rules_file" >/dev/null 2>&1; then
    echo "Error: $rules_file must contain a JSON object with a .rules array" >&2
    return 1
  fi

  # Each rule must have match, decision, reason
  local invalid
  invalid=$(jq '[.rules[] | select(has("match") and has("decision") and has("reason") | not)] | length' \
    "$rules_file" 2>/dev/null) || invalid="-1"
  if [ "$invalid" != "0" ]; then
    echo "Error: $invalid rules in $rules_file missing required fields (match, decision, reason)" >&2
    return 1
  fi

  # Namespace: all rule IDs must start with "<pack-name>-"
  local bad_ids
  bad_ids=$(jq -r --arg prefix "${pack_name}-" \
    '[.rules[] | .id // "" | select(. != "") | select(startswith($prefix) | not)] | length' \
    "$rules_file" 2>/dev/null) || bad_ids="0"
  if [ "$bad_ids" != "0" ]; then
    echo "Error: $bad_ids rule(s) in $rules_file have IDs that don't start with '${pack_name}-'" >&2
    echo "  Community packs must namespace all rule IDs as '<pack-name>-NNN'" >&2
    return 1
  fi

  return 0
}

# Return the path to the rules JSON file inside a pack directory.
# Uses pack.json's "rules_file" field if present, otherwise defaults to rules.json.
pack_rules_file() {
  local local_dir="$1"
  local rules_file
  rules_file=$(jq -r '.rules_file // "rules.json"' "$local_dir/pack.json" 2>/dev/null) || \
    rules_file="rules.json"
  printf '%s/%s' "$local_dir" "$rules_file"
}

# List installed community pack names (one per line).
pack_list_installed() {
  [ -d "$LANEKEEP_COMMUNITY_DIR" ] || return 0
  local d
  for d in "$LANEKEEP_COMMUNITY_DIR"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}pack.json" ] || continue
    basename "$d"
  done
}
