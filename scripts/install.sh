#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
INSTALL_DIR="$CODEX_HOME_DIR/bin"
TARGET="$INSTALL_DIR/bike-tool"

mkdir -p "$INSTALL_DIR"

echo "Building release binary..."
cd "$PROJECT_ROOT"
swift build -c release

echo "Installing to $TARGET"
cp ".build/release/bike-tool" "$TARGET"
chmod +x "$TARGET"

echo "Installed: $TARGET"
