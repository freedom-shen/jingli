#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-dd}"
MODE="${1:---fast}"
LOG_DIR="$ROOT/artifacts/self-test"
mkdir -p "$LOG_DIR"

echo "== unit: JingliCore =="
if ! (cd "$ROOT/Packages/JingliCore" && swift test) > "$LOG_DIR/unit.log" 2>&1; then
  tail -80 "$LOG_DIR/unit.log" >&2
  exit 1
fi
echo "ok"

echo "== app tests =="
if ! xcodebuild \
  -project "$ROOT/App/Jingli.xcodeproj" \
  -scheme Jingli \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  test > "$LOG_DIR/app-tests.log" 2>&1; then
  tail -80 "$LOG_DIR/app-tests.log" >&2
  exit 1
fi
echo "ok"

echo "== snapshot baseline =="
"$ROOT/scripts/snapshot.sh" compare | tee "$LOG_DIR/snapshot.json"

if [ "$MODE" = "--full" ]; then
  echo "== snapshot determinism =="
  "$ROOT/scripts/snapshot.sh" --determinism | tee "$LOG_DIR/determinism.json"
fi

echo "== agent spike =="
"$ROOT/scripts/agent-spike.sh" | tee "$LOG_DIR/agent-spike.log"

echo "self-test passed ($MODE)"
