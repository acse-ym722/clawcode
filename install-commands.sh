#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-$HOME/.local/bin}"

mkdir -p "$TARGET_DIR"
chmod +x "$ROOT_DIR/start.sh"

ln -sfn "$ROOT_DIR/start.sh" "$TARGET_DIR/claw-local"
ln -sfn "$ROOT_DIR/start.sh" "$TARGET_DIR/claw-poe"
ln -sfn "$ROOT_DIR/start.sh" "$TARGET_DIR/claw"
ln -sfn "$ROOT_DIR/start.sh" "$TARGET_DIR/claw-local-server"
ln -sfn "$ROOT_DIR/start.sh" "$TARGET_DIR/claw-doctor"

cat <<EOF
Installed commands into:
  $TARGET_DIR

Commands:
  claw
  claw-local
  claw-poe
  claw-local-server
  claw-doctor

If '$TARGET_DIR' is not in PATH yet, add this to your shell profile:
  export PATH="$TARGET_DIR:\$PATH"
EOF
