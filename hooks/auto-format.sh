#!/usr/bin/env bash
# Claude Code PostToolUse hook — auto-format files after Write/Edit
# Standalone hook (not sidecar-based). Formatting is a side-effect, not a governance decision.
# Exit 0 always — formatting failures never block the agent.
# No stdout — empty output = allow.

set -uo pipefail

# Read stdin (hook input)
INPUT=$(cat)

# Check env override
if [ "${LANEKEEP_AUTOFORMAT:-true}" = "false" ]; then
  exit 0
fi

# Extract tool_name and file_path
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# Only run for Write/Edit tools
case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# Skip if no file path
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Check exclude patterns from config
CONFIG_FILE="${LANEKEEP_CONFIG_FILE:-$PWD/lanekeep.json}"
[ -f "$CONFIG_FILE" ] || [ ! -f "$PWD/lanekeep.json.bak" ] || CONFIG_FILE="$PWD/lanekeep.json.bak"
if [ -f "$CONFIG_FILE" ]; then
  enabled=$(jq -r 'if .autoformat | has("enabled") then .autoformat.enabled else true end' "$CONFIG_FILE" 2>/dev/null) || enabled=true
  if [ "$enabled" = "false" ]; then
    exit 0
  fi
  # Check exclude patterns
  excluded=$(jq -r --arg fp "$FILE_PATH" '
    .autoformat.exclude_patterns // [] | .[] |
    . as $pat | $fp | test($pat) // false
  ' "$CONFIG_FILE" 2>/dev/null | grep -c "true") || excluded=0
  if [ "$excluded" -gt 0 ]; then
    exit 0
  fi
fi

# Detect formatter: config-file-first, then extension mapping
FORMATTER=""
FORMATTER_ARGS=()
DIR=$(dirname "$FILE_PATH")

detect_formatter() {
  local ext="${FILE_PATH##*.}"
  ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')

  # Config-file-first detection (check project root and parent dirs)
  local check_dir="$DIR"
  while [ "$check_dir" != "/" ] && [ -n "$check_dir" ]; do
    if [ -f "$check_dir/.prettierrc" ] || [ -f "$check_dir/.prettierrc.json" ] || \
       [ -f "$check_dir/.prettierrc.js" ] || [ -f "$check_dir/.prettierrc.yaml" ] || \
       [ -f "$check_dir/prettier.config.js" ]; then
      case "$ext" in
        js|jsx|ts|tsx|css|scss|less|html|json|md|yaml|yml|graphql|vue|svelte)
          if command -v prettier >/dev/null 2>&1; then
            FORMATTER="prettier"
            FORMATTER_ARGS=("--write")
            return 0
          fi
          ;;
      esac
    fi
    if [ -f "$check_dir/pyproject.toml" ]; then
      if grep -q '\[tool\.black\]' "$check_dir/pyproject.toml" 2>/dev/null; then
        case "$ext" in
          py)
            if command -v black >/dev/null 2>&1; then
              FORMATTER="black"
              FORMATTER_ARGS=("--quiet")
              return 0
            fi
            ;;
        esac
      fi
      if grep -q '\[tool\.ruff\]' "$check_dir/pyproject.toml" 2>/dev/null; then
        case "$ext" in
          py)
            if command -v ruff >/dev/null 2>&1; then
              FORMATTER="ruff"
              FORMATTER_ARGS=("format" "--quiet")
              return 0
            fi
            ;;
        esac
      fi
    fi
    if [ -f "$check_dir/.rustfmt.toml" ] || [ -f "$check_dir/rustfmt.toml" ]; then
      case "$ext" in
        rs)
          if command -v rustfmt >/dev/null 2>&1; then
            FORMATTER="rustfmt"
            FORMATTER_ARGS=()
            return 0
          fi
          ;;
      esac
    fi
    check_dir=$(dirname "$check_dir")
  done

  # Extension-based fallback
  case "$ext" in
    js|jsx|ts|tsx|css|scss|less|html|json|md|yaml|yml|vue|svelte)
      if command -v prettier >/dev/null 2>&1; then
        FORMATTER="prettier"
        FORMATTER_ARGS=("--write")
        return 0
      fi
      ;;
    py)
      if command -v black >/dev/null 2>&1; then
        FORMATTER="black"
        FORMATTER_ARGS=("--quiet")
        return 0
      elif command -v ruff >/dev/null 2>&1; then
        FORMATTER="ruff"
        FORMATTER_ARGS=("format" "--quiet")
        return 0
      fi
      ;;
    go)
      if command -v gofmt >/dev/null 2>&1; then
        FORMATTER="gofmt"
        FORMATTER_ARGS=("-w")
        return 0
      fi
      ;;
    rs)
      if command -v rustfmt >/dev/null 2>&1; then
        FORMATTER="rustfmt"
        FORMATTER_ARGS=()
        return 0
      fi
      ;;
    sh|bash|zsh)
      if command -v shfmt >/dev/null 2>&1; then
        FORMATTER="shfmt"
        FORMATTER_ARGS=("-w")
        return 0
      fi
      ;;
    rb)
      if command -v rubocop >/dev/null 2>&1; then
        FORMATTER="rubocop"
        FORMATTER_ARGS=("-a" "--silence-deprecations")
        return 0
      fi
      ;;
  esac

  return 1
}

if detect_formatter; then
  # Run formatter, suppress all output, never fail
  "$FORMATTER" "${FORMATTER_ARGS[@]}" "$FILE_PATH" >/dev/null 2>&1 || true
fi

exit 0
