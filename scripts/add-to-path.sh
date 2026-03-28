#!/usr/bin/env bash
# Add lanekeep/bin to your PATH permanently.
# Run from the repo root: bash scripts/add-to-path.sh
set -euo pipefail

LANEKEEP_BIN="$PWD/bin"

case "$SHELL" in
  */zsh)
    CONFIG="${ZDOTDIR:-$HOME}/.zshrc"
    LINE="export PATH=\"$LANEKEEP_BIN:\$PATH\""
    ;;
  */bash)
    if [[ "$(uname)" == "Darwin" ]]; then
      CONFIG="$HOME/.bash_profile"   # macOS Terminal opens login shells
    else
      CONFIG="$HOME/.bashrc"         # Linux / WSL
    fi
    LINE="export PATH=\"$LANEKEEP_BIN:\$PATH\""
    ;;
  */fish)
    # fish_add_path is idempotent — no config file edit needed
    fish -c "fish_add_path '$LANEKEEP_BIN'"
    echo "Done. Fish PATH updated (no restart needed)."
    exit 0
    ;;
  *)
    CONFIG="$HOME/.profile"          # POSIX fallback: ksh, dash, etc.
    LINE="export PATH=\"$LANEKEEP_BIN:\$PATH\""
    ;;
esac

if grep -qF "$LANEKEEP_BIN" "$CONFIG" 2>/dev/null; then
  echo "Already in $CONFIG — nothing to do."
else
  echo "$LINE" >> "$CONFIG"
  echo "Added to $CONFIG"
fi

echo ""
echo "Reload: source \"$CONFIG\""
