#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-dd}"
APP="$BUILD_DIR/Build/Products/Debug/Jingli.app"
CLI="$ROOT/Packages/JingliCore/.build/debug/jingli"
TMP="$(mktemp -d /tmp/jingli-agent.XXXXXX)"

if [ ! -d "$APP" ]; then
  echo "missing app at $APP; run xcodebuild first" >&2
  exit 2
fi

(
  cd "$ROOT/Packages/JingliCore"
  swift build --product jingli >/dev/null
)

export JINGLI_SUPPORT_DIR="$TMP"

cleanup() {
  if [ -n "${APP_PID:-}" ]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

"$APP/Contents/MacOS/Jingli" > "$TMP/app.log" 2>&1 &
APP_PID=$!

for _ in $(seq 1 40); do
  if [ -S "$TMP/agent.sock" ]; then
    break
  fi
  sleep 0.25
done

if [ ! -S "$TMP/agent.sock" ]; then
  echo "agent socket not created" >&2
  cat "$TMP/app.log" >&2 || true
  exit 1
fi

PERMISSIONS="$(stat -f '%Lp' "$TMP/agent.sock")"
if [ "$PERMISSIONS" != "600" ]; then
  echo "unexpected socket permissions: $PERMISSIONS" >&2
  exit 1
fi

"$CLI" ping > "$TMP/ping.json"
grep -q '"pong":true' "$TMP/ping.json"

PIDS=()
for index in $(seq 1 20); do
  "$CLI" task add "task-$index" > "$TMP/add-$index.json" &
  PIDS+=("$!")
done
for pid in "${PIDS[@]}"; do
  wait "$pid"
done

"$CLI" task count > "$TMP/count.json"
COUNT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["count"])' "$TMP/count.json")"
if [ "$COUNT" != "20" ]; then
  echo "expected 20 tasks, got $COUNT" >&2
  cat "$TMP/count.json" >&2
  exit 1
fi

echo "agent spike passed: socket=0600, ping=pong, tasks=$COUNT"
