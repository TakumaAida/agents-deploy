#!/usr/bin/env bash
# install.sh — create ~/.local/bin/agents-deploy symlink to src/deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$SCRIPT_DIR/deploy.sh"

if [[ ! -f "$DEPLOY" ]]; then
  echo "[error] deploy.sh not found at: $DEPLOY" >&2
  exit 1
fi

BIN_DIR="${AGENTS_DEPLOY_BIN_DIR:-$HOME/.local/bin}"
LINK="$BIN_DIR/agents-deploy"

mkdir -p "$BIN_DIR"

# Ensure executable
chmod +x "$DEPLOY"

if [[ -L "$LINK" ]]; then
  current="$(readlink "$LINK")"
  if [[ "$current" == "$DEPLOY" ]]; then
    echo "[info] already linked: $LINK -> $current"
  else
    echo "[info] replacing existing link: $LINK"
    ln -sf "$DEPLOY" "$LINK"
  fi
elif [[ -e "$LINK" ]]; then
  echo "[error] $LINK exists and is not a symlink. Remove it first." >&2
  exit 1
else
  ln -s "$DEPLOY" "$LINK"
  echo "[info] linked: $LINK -> $DEPLOY"
fi

# PATH sanity check
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "[warn] $BIN_DIR is not in your PATH."
    echo "       Add this to your shell rc:"
    echo "       export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

echo "[info] Done. Try: agents-deploy --help"
