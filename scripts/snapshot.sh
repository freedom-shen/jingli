#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-dd}"
APP="$BUILD_DIR/Build/Products/Debug/Jingli.app"
OUT="$ROOT/artifacts/snapshot"
BASELINE_DIR="$ROOT/Tests/Snapshots"
MODE="${1:-compare}"

SCENARIOS=(day-start today-running stats completion projects temporary task-detail)
export JINGLI_FAKE_NOW_MS="${JINGLI_FAKE_NOW_MS:-1792656000000}"
PANEL_SCENARIOS=(day-start today-running)

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

has_panel() {
  local fixture="$1"
  local item
  for item in "${PANEL_SCENARIOS[@]}"; do
    [ "$item" = "$fixture" ] && return 0
  done
  return 1
}

run_scenario() {
  local dir="$1"
  local fixture="$2"
  mkdir -p "$dir/support-$fixture"
  local args=(
    --snapshot
    --snapshot-fixture "$fixture"
    --snapshot-out "$dir/$fixture-main.png"
  )
  if has_panel "$fixture"; then
    args+=(--snapshot-panel-out "$dir/$fixture-panel.png")
  fi

  JINGLI_SUPPORT_DIR="$dir/support-$fixture" "$APP/Contents/MacOS/Jingli" "${args[@]}" \
    > "$dir/$fixture-run.log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 60); do
    if [ -f "$dir/$fixture-main.png" ]; then
      if ! has_panel "$fixture" || [ -f "$dir/$fixture-panel.png" ]; then
        break
      fi
    fi
    sleep 0.25
  done
  wait "$pid" || true

  if [ ! -f "$dir/$fixture-main.png" ]; then
    echo "snapshot missing: $dir/$fixture-main.png" >&2
    cat "$dir/$fixture-run.log" >&2 || true
    exit 1
  fi
  if has_panel "$fixture" && [ ! -f "$dir/$fixture-panel.png" ]; then
    echo "panel snapshot missing: $dir/$fixture-panel.png" >&2
    cat "$dir/$fixture-run.log" >&2 || true
    exit 1
  fi
}

run_all() {
  local dir="$1"
  local fixture
  for fixture in "${SCENARIOS[@]}"; do
    run_scenario "$dir" "$fixture"
  done
}

compare_images() {
  local baselineDir="$1"
  local currentDir="$2"
  local tag="$3"
  local fixture
  for fixture in "${SCENARIOS[@]}"; do
    "$DIFF" \
      --baseline "$baselineDir/$fixture-main.png" \
      --current "$currentDir/$fixture-main.png" \
      --diff "$OUT/$tag-$fixture-main.diff.png" \
      --max-mismatch 0 | tee "$OUT/$tag-$fixture-main.json"
    if has_panel "$fixture"; then
      "$DIFF" \
        --baseline "$baselineDir/$fixture-panel.png" \
        --current "$currentDir/$fixture-panel.png" \
        --diff "$OUT/$tag-$fixture-panel.diff.png" \
        --max-mismatch 0 | tee "$OUT/$tag-$fixture-panel.json"
    fi
  done
}

case "$MODE" in
  --update)
    run_all "$OUT/current"
    mkdir -p "$BASELINE_DIR"
    rm -f "$BASELINE_DIR"/phase0-*.png
    for fixture in "${SCENARIOS[@]}"; do
      cp "$OUT/current/$fixture-main.png" "$BASELINE_DIR/$fixture-main.png"
      if has_panel "$fixture"; then
        cp "$OUT/current/$fixture-panel.png" "$BASELINE_DIR/$fixture-panel.png"
      fi
    done
    echo "updated baselines in $BASELINE_DIR"
    ;;
  --determinism)
    run_all "$OUT/current"
    run_all "$OUT/second"
    compare_images "$OUT/current" "$OUT/second" "determinism"
    echo "determinism passed (0 mismatch)"
    ;;
  compare|--compare)
    for fixture in "${SCENARIOS[@]}"; do
      if [ ! -f "$BASELINE_DIR/$fixture-main.png" ]; then
        echo "missing baseline $fixture-main.png; run scripts/snapshot.sh --update" >&2
        exit 2
      fi
    done
    run_all "$OUT/current"
    compare_images "$BASELINE_DIR" "$OUT/current" "baseline"
    echo "snapshot passed"
    ;;
  *)
    echo "usage: scripts/snapshot.sh [compare|--update|--determinism]" >&2
    exit 2
    ;;
esac
