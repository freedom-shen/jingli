#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-dd}"
APP="$BUILD_DIR/Build/Products/Debug/Jingli.app"
OUT="$ROOT/artifacts/snapshot"
BASELINE_DIR="$ROOT/Tests/Snapshots"
MODE="${1:-compare}"

if [ ! -d "$APP" ]; then
  echo "missing app at $APP; run xcodebuild first" >&2
  exit 2
fi

rm -rf "$OUT"
mkdir -p "$OUT/current"
if [ "$MODE" = "--determinism" ]; then
  mkdir -p "$OUT/second"
fi

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

compare_images() {
  local baselineMain="$1"
  local baselinePanel="$2"
  local currentDir="$3"
  local tag="$4"
  "$DIFF" \
    --baseline "$baselineMain" \
    --current "$currentDir/main.png" \
    --diff "$OUT/$tag-main.diff.png" \
    --max-mismatch 0 | tee "$OUT/$tag-main.json"
  "$DIFF" \
    --baseline "$baselinePanel" \
    --current "$currentDir/panel.png" \
    --diff "$OUT/$tag-panel.diff.png" \
    --max-mismatch 0 | tee "$OUT/$tag-panel.json"
}

case "$MODE" in
  --update)
    run_once "$OUT/current"
    mkdir -p "$BASELINE_DIR"
    cp "$OUT/current/main.png" "$BASELINE_DIR/phase0-main.png"
    cp "$OUT/current/panel.png" "$BASELINE_DIR/phase0-panel.png"
    echo "updated baselines: $BASELINE_DIR/phase0-main.png, phase0-panel.png"
    ;;
  --determinism)
    run_once "$OUT/current"
    run_once "$OUT/second"
    compare_images "$OUT/current/main.png" "$OUT/current/panel.png" "$OUT/second" "determinism"
    echo "determinism passed (0 mismatch)"
    ;;
  compare|--compare)
    if [ ! -f "$BASELINE_DIR/phase0-main.png" ] || [ ! -f "$BASELINE_DIR/phase0-panel.png" ]; then
      echo "missing baselines; run scripts/snapshot.sh --update" >&2
      exit 2
    fi
    run_once "$OUT/current"
    compare_images "$BASELINE_DIR/phase0-main.png" "$BASELINE_DIR/phase0-panel.png" "$OUT/current" "baseline"
    echo "snapshot passed"
    ;;
  *)
    echo "usage: scripts/snapshot.sh [compare|--update|--determinism]" >&2
    exit 2
    ;;
esac
