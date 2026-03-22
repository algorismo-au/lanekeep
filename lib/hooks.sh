#!/usr/bin/env bash
# hooks.sh — normalize Claude Code hook format (flat → nested)
#
# Claude Code expects nested format:
#   {"matcher": "", "hooks": [{"type": "command", "command": "...", "timeout": 10000}]}
#
# Old/broken installs may have flat format:
#   {"type": "command", "command": "...", "timeout": 10000}

# normalize_hook_format <settings_file>
# Converts any flat-format hook entries to nested format. Idempotent.
# Returns 0 if changes were made, 1 if already clean.
normalize_hook_format() {
  local settings_file="$1"
  [ -f "$settings_file" ] || return 1

  local original new
  original=$(cat "$settings_file")
  new=$(printf '%s' "$original" | jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= [
          .[] |
          if has("type") and (has("hooks") | not) then
            # Flat format → wrap into nested
            {matcher: (.matcher // ""), hooks: [del(.matcher)]}
          else
            .  # Already nested — leave as-is
          end
        ]
      )
    else . end
  ')

  if [ "$original" = "$new" ]; then
    return 1
  fi
  printf '%s\n' "$new" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "$settings_file"
  return 0
}

# validate_hook_format <settings_file>
# Returns 0 if all hooks are nested, 1 if any flat entries exist.
validate_hook_format() {
  local settings_file="$1"
  [ -f "$settings_file" ] || return 1

  local flat_count
  flat_count=$(jq '
    [.hooks // {} | to_entries[] | .value[] | select(has("type") and (has("hooks") | not))] | length
  ' "$settings_file" 2>/dev/null) || return 1

  [ "$flat_count" -eq 0 ]
}
