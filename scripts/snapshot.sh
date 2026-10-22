#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-dd}"
APP="$BUILD_DIR/Build/Products/Debug/Jingli.app"
OUT="${1:-$ROOT/artifacts/snapshot-spike}"

if [ ! -d "$APP" ]; then
  echo "missing app at $APP; run xcodebuild first" >&2
  exit 2
fi

rm -rf "$OUT"
mkdir -p "$OUT/run1" "$OUT/run2"

(
  cd "$ROOT/Packages/JingliCore"
  swift build --product jingli-snapshot-diff >/dev/null
)
DIFF="$ROOT/Packages/JingliCore/.build/debug/jingli-snapshot-diff"

run_once() {
  local dir="$1"
  "$APP/Contents/MacOS/Jingli" \
    --snapshot \
    --snapshot-out "$dir/main.png" \
    --snapshot-panel-out "$dir/panel.png" \
    > "$dir/run.log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 40); do
    if [ -f "$dir/main.png" ] && [ -f "$dir/panel.png" ]; then
      break
    fi
    sleep 0.25
  done
  wait "$pid" || true
  if [ ! -f "$dir/main.png" ] || [ ! -f "$dir/panel.png" ]; then
    echo "snapshot missing in $dir" >&2
    cat "$dir/run.log" >&2 || true
    exit 1
  fi
}

run_once "$OUT/run1"
run_once "$OUT/run2"

"$DIFF" \
  --baseline "$OUT/run1/main.png" \
  --current "$OUT/run2/main.png" \
  --diff "$OUT/main.diff.png" \
  --max-mismatch 0 | tee "$OUT/main.json"

"$DIFF" \
  --baseline "$OUT/run1/panel.png" \
  --current "$OUT/run2/panel.png" \
  --diff "$OUT/panel.diff.png" \
  --max-mismatch 0 | tee "$OUT/panel.json"

echo "snapshots: $OUT"
