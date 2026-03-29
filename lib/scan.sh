#!/usr/bin/env bash
# Deterministic security scanner for imported plugins.
#
# Bash port of trailofbits/skills-curated scan_plugin.py
#
# Scans plugin directories for:
#   1. Unicode tricks (bidi overrides, zero-width chars, homoglyphs)
#   2. Network access (URLs, curl/wget, Python/Node imports)
#   3. Destructive commands (rm -rf, git reset --hard, etc.)
#   4. Code execution (pipe-to-shell, eval/exec, subprocess)
#   5. Credential access (SSH keys, AWS config, etc.)
#   6. Encoded payloads (hex escapes, fromCharCode, atob/btoa)
#   7. Privilege escalation (sudo, setuid, chmod +s)
#   8. Compiled bytecode (.pyc, .pyo, __pycache__)
#
# Exit codes: 0 = clean, 1 = usage error, 2 = BLOCK findings, 3 = WARN only

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CODE_EXTENSIONS="py sh js ts swift ps1 json yml yaml"
SKIP_FILENAMES="LICENSE LICENSE.md LICENSE.txt"

# ---------------------------------------------------------------------------
# Findings accumulator
# ---------------------------------------------------------------------------

SCAN_BLOCK_COUNT=0
SCAN_WARN_COUNT=0
SCAN_FINDINGS=""

_add_finding() {
  local level="$1" category="$2" path="$3" lineno="$4" detail="$5"
  if [ "$level" = "BLOCK" ]; then
    SCAN_BLOCK_COUNT=$((SCAN_BLOCK_COUNT + 1))
  else
    SCAN_WARN_COUNT=$((SCAN_WARN_COUNT + 1))
  fi
  # Tab-separated record: level \t category \t path \t lineno \t detail
  SCAN_FINDINGS="${SCAN_FINDINGS}${level}	${category}	${path}	${lineno}	${detail}
"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_is_code_ext() {
  local suffix="$1"
  case " $CODE_EXTENSIONS " in
    *" $suffix "*) return 0 ;;
  esac
  return 1
}

_is_skip_file() {
  local name="$1"
  case " $SKIP_FILENAMES " in
    *" $name "*) return 0 ;;
  esac
  return 1
}

# Detect if file is binary by checking first 8KB for null bytes
_is_binary() {
  head -c 8192 "$1" 2>/dev/null | grep -qP '\x00'
}

# Returns 0 if given line index is inside a fenced code block in markdown.
# Expects _MD_CODE_LINES to be set (space-separated list of line indices).
_in_md_code_block() {
  local idx="$1"
  case " $_MD_CODE_LINES " in
    *" $idx "*) return 0 ;;
  esac
  return 1
}

# Build list of line indices inside fenced code blocks for a markdown file.
# Sets _MD_CODE_LINES as space-separated indices.
_build_md_code_ranges() {
  local file="$1"
  _MD_CODE_LINES=""
  local fence_start=-1 fence_char="" fence_len=0
  local i=0
  while IFS= read -r line; do
    local stripped="${line#"${line%%[! ]*}"}"  # lstrip
    if [ "$fence_start" -eq -1 ]; then
      # Check for fence open
      if [[ "$stripped" =~ ^(\`{3,}) ]] || [[ "$stripped" =~ ^(~{3,}) ]]; then
        fence_char="${BASH_REMATCH[1]:0:1}"
        fence_len="${#BASH_REMATCH[1]}"
        fence_start=$i
      fi
    else
      # Check for fence close
      local close="${stripped%%[! "$fence_char"]*}"
      # Verify close is only fence chars and long enough
      if [ -n "$close" ] && [ "${#close}" -ge "$fence_len" ]; then
        # Simpler: check if stripped (after removing trailing ws) is all fence_char
        local clean
        clean=$(printf '%s' "$stripped" | sed 's/[[:space:]]*$//')
        if [ -n "$clean" ] && [ -z "${clean//[$fence_char]/}" ]; then
          # Mark all lines from fence_start to i as code
          local j=$fence_start
          while [ "$j" -le "$i" ]; do
            _MD_CODE_LINES="$_MD_CODE_LINES $j"
            j=$((j + 1))
          done
          fence_start=-1
          fence_char=""
          fence_len=0
        fi
      fi
    fi
    i=$((i + 1))
  done < "$file"
}

# Returns 0 if line is in a code context
_is_code_context() {
  local line_idx="$1" suffix="$2"
  if _is_code_ext "$suffix"; then
    return 0
  fi
  if [ "$suffix" = "md" ] && _in_md_code_block "$line_idx"; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Check functions
# ---------------------------------------------------------------------------

_check_unicode() {
  local line="$1" line_idx="$2" rel_path="$3" suffix="$4"
  local lineno=$((line_idx + 1))

  # Bidi overrides: U+202A-202E, U+2066-2069
  if printf '%s' "$line" | grep -qP '[\x{202A}-\x{202E}\x{2066}-\x{2069}]'; then
    local chars
    chars=$(printf '%s' "$line" | grep -oP '[\x{202A}-\x{202E}\x{2066}-\x{2069}]' | head -1)
    local cp
    cp=$(printf '%s' "$chars" | od -An -tx4 | head -1 | tr -d ' ' | sed 's/^0*//' | tr '[:lower:]' '[:upper:]')
    _add_finding "BLOCK" "bidi-override" "$rel_path" "$lineno" "U+${cp}"
  fi

  # Zero-width chars: U+200B, U+200C, U+200D, U+FEFF, U+00AD
  if printf '%s' "$line" | grep -qP '[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{00AD}]'; then
    local chars
    chars=$(printf '%s' "$line" | grep -oP '[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{00AD}]' | head -1)
    local cp
    cp=$(printf '%s' "$chars" | od -An -tx4 | head -1 | tr -d ' ' | sed 's/^0*//' | tr '[:lower:]' '[:upper:]')
    _add_finding "BLOCK" "zero-width-char" "$rel_path" "$lineno" "U+${cp}"
  fi

  # Homoglyphs: non-ASCII letters in code context
  if _is_code_context "$line_idx" "$suffix"; then
    if printf '%s' "$line" | grep -qP '[^\x00-\x7F]'; then
      # Skip if already caught by bidi/zero-width
      if ! printf '%s' "$line" | grep -qP '[\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}\x{200C}\x{200D}\x{FEFF}\x{00AD}]'; then
        _add_finding "BLOCK" "homoglyph" "$rel_path" "$lineno" "non-ASCII character in code context"
      fi
    fi
  fi
}

_check_network() {
  local line="$1" line_idx="$2" rel_path="$3" suffix="$4"
  local lineno=$((line_idx + 1))
  local is_code=false
  _is_code_context "$line_idx" "$suffix" && is_code=true

  # Punycode URLs — always BLOCK
  if printf '%s' "$line" | grep -qP 'https?://[^\s/]*xn--'; then
    local url
    url=$(printf '%s' "$line" | grep -oP 'https?://[^\s/]*xn--\S*' | head -1)
    _add_finding "BLOCK" "punycode-url" "$rel_path" "$lineno" "$url"
  fi

  # External URLs
  local urls
  urls=$(printf '%s' "$line" | grep -oP 'https?://\S+' 2>/dev/null) || true
  if [ -n "$urls" ]; then
    while IFS= read -r url; do
      url="${url%)}"  # strip trailing paren from markdown links
      # Skip punycode (already flagged)
      if printf '%s' "$url" | grep -qP 'xn--'; then
        continue
      fi
      # Skip GitHub attribution URLs in prose
      if [ "$is_code" = "false" ] && printf '%s' "$url" | grep -qP '^https?://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/?$'; then
        continue
      fi
      _add_finding "WARN" "external-url" "$rel_path" "$lineno" "$url"
    done <<< "$urls"
  fi

  # Network commands (only in code)
  if [ "$is_code" = "true" ]; then
    if printf '%s' "$line" | grep -qP '\b(?:curl|wget|nc|ncat|socat|ssh|scp|rsync)\b|openssl\s+s_client'; then
      local detail="${line:0:120}"
      detail="${detail#"${detail%%[! ]*}"}"
      _add_finding "WARN" "network-cmd" "$rel_path" "$lineno" "$detail"
    fi
  fi

  # Python network imports
  if printf '%s' "$line" | grep -qP '^\s*(?:import|from)\s+(?:requests|httpx|urllib|aiohttp|http\.client|socket|websocket)\b'; then
    local detail="${line:0:120}"
    detail="${detail#"${detail%%[! ]*}"}"
    _add_finding "WARN" "network-import" "$rel_path" "$lineno" "$detail"
  fi

  # Node network patterns (only in code)
  if [ "$is_code" = "true" ]; then
    if printf '%s' "$line" | grep -qP "\bfetch\s*\(|(?:require|import)\s*\(?['\"](?:axios|node-fetch|http|https)['\"]|\b(?:http|https)\.get\s*\("; then
      local detail="${line:0:120}"
      detail="${detail#"${detail%%[! ]*}"}"
      _add_finding "WARN" "network-import" "$rel_path" "$lineno" "$detail"
    fi
  fi
}

_check_destructive() {
  local line="$1" line_idx="$2" rel_path="$3" suffix="$4"
  local lineno=$((line_idx + 1))
  _is_code_context "$line_idx" "$suffix" || return 0

  if printf '%s' "$line" | grep -qP '\brm\b(?=.*(\s-[a-zA-Z]*r[a-zA-Z]*(\s|$)|\s--recursive\b))(?=.*(\s-[a-zA-Z]*f[a-zA-Z]*(\s|$)|\s--force\b))|\brm\s+--recursive\b|\brmdir\b|\bshred\b|\bunlink\b|\bgit\s+clean\b(?=.*\s-[a-zA-Z]*f[a-zA-Z]*(\s|$))(?=.*\s-[a-zA-Z]*d[a-zA-Z]*(\s|$))|\bgit\s+reset\b(?=.*\s--hard(\s|$))|\bgit\s+push\b(?=.*\s(--force(?!-)(\s|$)|-[a-zA-Z]*f(\s|$)))|\bgit\s+branch\s+-D\b|\bchmod\s+(?:-R\s+)?777\b|\bdd\s+if=|\bmkfs\b|\bformat\s+[A-Za-z]:'; then
    local detail="${line:0:120}"
    detail="${detail#"${detail%%[! ]*}"}"
    _add_finding "WARN" "destructive-cmd" "$rel_path" "$lineno" "$detail"
  fi
}

_check_code_execution() {
  local line="$1" line_idx="$2" rel_path="$3" suffix="$4"
  local lineno=$((line_idx + 1))
  _is_code_context "$line_idx" "$suffix" || return 0

  local detail="${line:0:120}"
  detail="${detail#"${detail%%[! ]*}"}"

  # Pipe-to-shell — BLOCK
  if printf '%s' "$line" | grep -qP '\|\s*(?:bash|sh|zsh|dash|python[23]?|perl|ruby|node)\b|\b(?:bash|sh|zsh)\s+-c\s|\bsource\s+<\(|\beval\s+"\$\('; then
    _add_finding "BLOCK" "pipe-to-shell" "$rel_path" "$lineno" "$detail"
  fi

  # Eval/exec — WARN
  if printf '%s' "$line" | grep -qP "\beval\s*\(|\bexec\s*\(|\bFunction\s*\(|\b__import__\s*\(|\bimportlib\.import_module\s*\(|\bcompile\s*\([^)]*['\"]exec['\"]"; then
    _add_finding "WARN" "eval-exec" "$rel_path" "$lineno" "$detail"
  fi

  # Python shell-out — WARN
  if printf '%s' "$line" | grep -qP '\bsubprocess\b|\bos\.system\s*\(|\bos\.popen\s*\(|\bos\.exec[lv]p?\s*\('; then
    _add_finding "WARN" "py-shellout" "$rel_path" "$lineno" "$detail"
  fi
}

_check_credential_access() {
  local line="$1" line_idx="$2" rel_path="$3" suffix="$4"
  _is_code_context "$line_idx" "$suffix" || return 0

  # shellcheck disable=SC2088  # tilde is a literal regex char here, not a path expansion
  if printf '%s' "$line" | grep -qP '~/\.ssh\b|~/\.aws\b|~/\.gnupg\b|~/\.config/gh\b|~/\.netrc\b|/etc/shadow\b|\bid_rsa\b|\bid_ed25519\b'; then
    local lineno=$((line_idx + 1))
    local detail="${line:0:120}"
    detail="${detail#"${detail%%[! ]*}"}"
    _add_finding "BLOCK" "credential-access" "$rel_path" "$lineno" "$detail"
  fi
}

_check_obfuscation() {
  local line="$1" line_idx="$2" rel_path="$3" suffix="$4"
  _is_code_context "$line_idx" "$suffix" || return 0

  if printf '%s' "$line" | grep -qP '(?:\\x[0-9a-fA-F]{2}){8,}|\bString\.fromCharCode\s*\(|\bchr\s*\(\s*0x[0-9a-fA-F]|\batob\s*\(|\bbtoa\s*\('; then
    local detail="${line:0:120}"
    detail="${detail#"${detail%%[! ]*}"}"
    _add_finding "WARN" "encoded-payload" "$rel_path" "$lineno" "$detail"
  fi
}

_check_privilege() {
  local line="$1" line_idx="$2" rel_path="$3" suffix="$4"
  _is_code_context "$line_idx" "$suffix" || return 0

  if printf '%s' "$line" | grep -qP '\bsudo\b|\bdoas\b|\bchown\s+root\b|\bsetuid\b|\bchmod\s+[ugo]*s'; then
    local detail="${line:0:120}"
    detail="${detail#"${detail%%[! ]*}"}"
    _add_finding "WARN" "privilege-cmd" "$rel_path" "$lineno" "$detail"
  fi
}

# ---------------------------------------------------------------------------
# File / plugin scanning
# ---------------------------------------------------------------------------

scan_file() {
  local file="$1" rel_path="$2"
  local name
  name=$(basename "$file")

  # Skip license files
  if _is_skip_file "$name"; then
    return 0
  fi

  # Get extension without dot
  local suffix=""
  case "$name" in
    *.*) suffix="${name##*.}" ;;
  esac

  # Compiled bytecode
  case "$suffix" in
    pyc|pyo)
      _add_finding "BLOCK" "compiled-bytecode" "$rel_path" "0" "compiled Python bytecode (.$suffix)"
      return 0
      ;;
  esac

  # Skip binary files
  if _is_binary "$file"; then
    return 0
  fi

  # Build markdown code ranges if needed
  _MD_CODE_LINES=""
  if [ "$suffix" = "md" ]; then
    _build_md_code_ranges "$file"
  fi

  local line_idx=0
  while IFS= read -r line || [ -n "$line" ]; do
    # Unicode checks (only on non-ASCII lines)
    if printf '%s' "$line" | grep -qP '[^\x00-\x7F]'; then
      _check_unicode "$line" "$line_idx" "$rel_path" "$suffix"
    fi

    _check_network "$line" "$line_idx" "$rel_path" "$suffix"
    _check_destructive "$line" "$line_idx" "$rel_path" "$suffix"
    _check_code_execution "$line" "$line_idx" "$rel_path" "$suffix"
    _check_credential_access "$line" "$line_idx" "$rel_path" "$suffix"
    _check_obfuscation "$line" "$line_idx" "$rel_path" "$suffix"
    _check_privilege "$line" "$line_idx" "$rel_path" "$suffix"

    line_idx=$((line_idx + 1))
  done < "$file"
}

scan_plugin() {
  local plugin_dir="$1"
  local base_dir
  base_dir=$(dirname "$plugin_dir")

  # Check for __pycache__ directories
  while IFS= read -r dir; do
    local rel
    rel="${dir#"$base_dir"/}"
    _add_finding "BLOCK" "compiled-bytecode" "$rel" "0" "__pycache__ directory (unreviewable bytecode)"
  done < <(find "$plugin_dir" -type d -name "__pycache__" 2>/dev/null | sort)

  # Scan all files
  while IFS= read -r file; do
    local rel
    rel="${file#"$base_dir"/}"
    scan_file "$file" "$rel"
  done < <(find "$plugin_dir" -type f 2>/dev/null | sort)
}

# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

format_text() {
  if [ -z "$SCAN_FINDINGS" ]; then
    echo "No findings."
    return
  fi

  while IFS=$'\t' read -r level category path lineno detail; do
    [ -z "$level" ] && continue
    local tag
    if [ "$level" = "BLOCK" ]; then
      tag="BLOCK"
    else
      tag="WARN "
    fi
    printf '%-5s  %-18s %s:%-6s %s\n' "$tag" "$category" "$path" "$lineno" "$detail"
  done <<< "$SCAN_FINDINGS"

  printf '\nSummary: %d finding(s) — %d BLOCK, %d WARN\n' \
    "$((SCAN_BLOCK_COUNT + SCAN_WARN_COUNT))" "$SCAN_BLOCK_COUNT" "$SCAN_WARN_COUNT" >&2
}

_escape_md_pipe() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

format_markdown() {
  if [ -z "$SCAN_FINDINGS" ]; then
    printf '<!-- security-scan -->\nNo security findings.\n'
    return
  fi

  local total=$((SCAN_BLOCK_COUNT + SCAN_WARN_COUNT))
  printf '<!-- security-scan -->\n'
  printf '## Security Scanner Report\n\n'
  printf '**%d** finding(s): **%d** BLOCK, **%d** WARN\n' "$total" "$SCAN_BLOCK_COUNT" "$SCAN_WARN_COUNT"

  # BLOCK findings table
  if [ "$SCAN_BLOCK_COUNT" -gt 0 ]; then
    printf '\n### BLOCK findings\n\n'
    printf '| Category | File | Line | Detail |\n'
    printf '|----------|------|------|--------|\n'
    while IFS=$'\t' read -r level category path lineno detail; do
      [ "$level" = "BLOCK" ] || continue
      detail="${detail:0:80}"
      detail=$(_escape_md_pipe "$detail")
      # shellcheck disable=SC2016  # backticks in format string are markdown literal chars, not expansions
      printf '| %s | %s | %s | `%s` |\n' "$category" "$path" "$lineno" "$detail"
    done <<< "$SCAN_FINDINGS"
  fi

  # WARN findings table
  if [ "$SCAN_WARN_COUNT" -gt 0 ]; then
    printf '\n### WARN findings\n\n'
    printf '| Category | File | Line | Detail |\n'
    printf '|----------|------|------|--------|\n'
    while IFS=$'\t' read -r level category path lineno detail; do
      [ "$level" = "WARN" ] || continue
      detail="${detail:0:80}"
      detail=$(_escape_md_pipe "$detail")
      # shellcheck disable=SC2016  # backticks in format string are markdown literal chars, not expansions
      printf '| %s | %s | %s | `%s` |\n' "$category" "$path" "$lineno" "$detail"
    done <<< "$SCAN_FINDINGS"
  fi
}

# ---------------------------------------------------------------------------
# Plugin discovery
# ---------------------------------------------------------------------------

discover_plugins() {
  local target="$1"
  local name
  name=$(basename "$target")

  if [ "$name" = "plugins" ]; then
    # Parent directory — find subdirs with .claude-plugin
    local found=0
    while IFS= read -r d; do
      if [ -d "$d/.claude-plugin" ]; then
        printf '%s\n' "$d"
        found=1
      fi
    done < <(find "$target" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    [ "$found" -eq 1 ] && return 0
    echo "Error: no plugin directories found in $target" >&2
    return 1
  fi

  if [ -d "$target/.claude-plugin" ]; then
    printf '%s\n' "$target"
    return 0
  fi

  echo "Error: $target is not a plugin directory (missing .claude-plugin/) and is not a plugins/ parent" >&2
  return 1
}
