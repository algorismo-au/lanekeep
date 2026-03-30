#!/usr/bin/env bash
# Wire LaneKeep git hooks into your local repo.
# Run from the repo root: bash scripts/setup-dev-hooks.sh
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SRC="$REPO_ROOT/scripts/git-hooks"
HOOKS_DEST="$REPO_ROOT/.git/hooks"

for hook in "$HOOKS_SRC"/*; do
  name="$(basename "$hook")"
  dest="$HOOKS_DEST/$name"
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    echo "Warning: $dest exists and is not a symlink — skipping (back it up manually)."
    continue
  fi
  chmod +x "$hook"
  ln -sf "$hook" "$dest"
  echo "Installed: .git/hooks/$name → scripts/git-hooks/$name"
done

echo ""
echo "Done. Hooks active for this repo."
echo ""
echo "Usage:"
echo "  git push              # runs targeted tests automatically"
echo "  SKIP_TESTS=1 git push # bypass hook (WIP pushes)"
echo "  FULL_TESTS=1 git push # force full suite"
