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

json() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"]'"$1"')'
}

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

"$CLI" project add "工作" > "$TMP/project.json"
"$CLI" task add "写周报" --project 工作 --lane main --date today > "$TMP/task.json"
TASK_ID="$(json '["id"]' < "$TMP/task.json")"

"$CLI" day plan "$TASK_ID" --dry-run > "$TMP/plan-dry.json"
python3 - "$TMP/plan-dry.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))["result"]
assert result["dryRun"] is True, result
assert result["mainCount"] == 1, result
PY

"$CLI" day plan "$TASK_ID" > "$TMP/plan.json"
"$CLI" day start > "$TMP/start.json"
python3 - "$TMP/start.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))["result"]
assert result["dayStarted"] is True, result
assert result["taskCount"] == 1, result
PY

"$CLI" task add "临时插单" --lane temporary > "$TMP/temp.json"
TEMP_ID="$(json '["id"]' < "$TMP/temp.json")"
python3 - "$TMP/temp.json" <<'PY'
import datetime, json, sys
task = json.load(open(sys.argv[1]))["result"]
assert task["lane"] == "temporary", task
# 「新的一天」默认 8 点起：8 点前仍算前一天，口径与 App 内 DayKey 一致
now = datetime.datetime.now()
expected = (now if now.hour >= 8 else now - datetime.timedelta(days=1)).date().isoformat()
assert task["plannedDate"] == expected, task
PY

"$CLI" today > "$TMP/today-temp.json"
python3 - "$TMP/today-temp.json" "$TEMP_ID" <<'PY'
import json, sys
tasks = json.load(open(sys.argv[1]))["result"]["tasks"]
assert any(t["id"] == sys.argv[2] for t in tasks), tasks
PY

"$CLI" task add "先记下的临时任务" --lane temporary --undated > "$TMP/undated.json"
python3 - "$TMP/undated.json" <<'PY'
import json, sys
task = json.load(open(sys.argv[1]))["result"]
assert task["lane"] == "temporary", task
assert "plannedDate" not in task, task
PY

"$CLI" today > "$TMP/today-undated.json"
python3 - "$TMP/today-undated.json" <<'PY'
import json, sys
tasks = json.load(open(sys.argv[1]))["result"]["tasks"]
assert all(t["title"] != "先记下的临时任务" for t in tasks), tasks
PY

if "$CLI" task add "不该加的主线" --lane main --date today > "$TMP/main-locked.json" 2>/dev/null; then
  echo "main task should be locked after day start" >&2
  exit 1
fi
grep -q '今天已经开始' "$TMP/main-locked.json"

"$CLI" focus start "$TASK_ID" > "$TMP/focus-start.json"
python3 - "$TMP/focus-start.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))["result"]
assert result["active"] is True, result
assert result["phase"] == "running", result
PY

"$CLI" focus status > "$TMP/focus-status.json"
grep -q '"active":true' "$TMP/focus-status.json"
"$CLI" focus pause > "$TMP/focus-pause.json"
grep -q '"phase":"paused"' "$TMP/focus-pause.json"
"$CLI" focus resume > "$TMP/focus-resume.json"
grep -q '"phase":"running"' "$TMP/focus-resume.json"
"$CLI" focus stop --confirm > "$TMP/focus-stop.json"
grep -q '"active":false' "$TMP/focus-stop.json"

if "$CLI" day reset > "$TMP/reset-denied.json" 2>/dev/null; then
  echo "day reset without --confirm should fail" >&2
  exit 1
fi
grep -q 'confirm' "$TMP/reset-denied.json"

"$CLI" task complete "$TASK_ID" > "$TMP/complete.json"
grep -q '"done":true' "$TMP/complete.json"
"$CLI" undo --confirm > "$TMP/undo.json"
grep -q '"undone"' "$TMP/undo.json"
"$CLI" task list --all > "$TMP/tasks-after-undo.json"
python3 - "$TMP/tasks-after-undo.json" "$TASK_ID" <<'PY'
import json, sys
tasks = json.load(open(sys.argv[1]))["result"]["tasks"]
task = next(t for t in tasks if t["id"] == sys.argv[2])
assert task["done"] is False, task
PY

"$CLI" stats > "$TMP/stats.json"
python3 - "$TMP/stats.json" <<'PY'
import json, sys
stats = json.load(open(sys.argv[1]))["result"]
assert stats["pomodoros"] == 0, stats
PY

"$CLI" stats --days 2 > "$TMP/history.json"
python3 - "$TMP/history.json" <<'PY'
import json, sys
days = json.load(open(sys.argv[1]))["result"]["days"]
assert len(days) == 2, days
assert days[0]["date"] > days[1]["date"], days
PY

"$CLI" stats --date "$(date +%F)" > "$TMP/history-day.json"
python3 - "$TMP/history-day.json" <<'PY'
import json, sys
days = json.load(open(sys.argv[1]))["result"]["days"]
assert len(days) == 1, days
PY

"$CLI" events > "$TMP/events.json"
python3 - "$TMP/events.json" <<'PY'
import json, sys
events = json.load(open(sys.argv[1]))["result"]["events"]
assert len(events) >= 4, events
assert events[0]["actor"] == "agent", events[0]
PY

echo "agent spike passed: socket=0600, ping=pong, tasks=$COUNT, plan+focus+undo=ok"
