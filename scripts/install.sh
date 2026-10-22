#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SKILL_DIR="${SKILL_DIR:-$HOME/.agents/skills}"

echo "building jingli CLI (release)…"
(
  cd "$ROOT/Packages/JingliCore"
  swift build -c release --product jingli
)

mkdir -p "$BIN_DIR"
cp "$ROOT/Packages/JingliCore/.build/release/jingli" "$BIN_DIR/jingli"
chmod +x "$BIN_DIR/jingli"

mkdir -p "$SKILL_DIR"
ln -sfn "$ROOT/skill/jingli" "$SKILL_DIR/jingli"

echo "installed:"
echo "  $BIN_DIR/jingli"
echo "  $SKILL_DIR/jingli -> $ROOT/skill/jingli"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: add $BIN_DIR to PATH" ;;
esac
