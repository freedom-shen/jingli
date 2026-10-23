#!/usr/bin/env bash
set -euo pipefail

# 模拟一天：短计时跑完 3 轮、暂停 / 继续、加 / 移任务、休息、再来一轮、统计、重置、备份、跨天。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-dd}"
APP="$BUILD_DIR/Build/Products/Debug/Jingli.app"
CLI="$ROOT/Packages/JingliCore/.build/debug/jingli"
TMP="$(mktemp -d /tmp/jingli-dogfood.XXXXXX)"
FAKE="$TMP/fake-shortcuts"
CALLS="$TMP/focus-calls.log"

cat > "$FAKE" <<'FAKE_EOF'
#!/bin/bash
case "$1" in
  list) echo "Jingli Focus On"; echo "Jingli Focus Off" ;;
  run) echo "$2" >> "$JINGLI_FAKE_CALLS" ;;
esac
exit 0
FAKE_EOF
chmod +x "$FAKE"

if [ ! -d "$APP" ]; then
  echo "missing app at $APP; run xcodebuild first" >&2
  exit 2
fi

(
  cd "$ROOT/Packages/JingliCore"
  swift build --product jingli >/dev/null
)

export JINGLI_SUPPORT_DIR="$TMP"
export JINGLI_FAKE_CALLS="$CALLS"
export JINGLI_SHORTCUTS_BIN="$FAKE"
export JINGLI_TIMER_SECONDS=2
export JINGLI_BREAK_SECONDS=1
export JINGLI_NO_NOTIFICATIONS=1

APP_PID=""
start_app() {
  "$APP/Contents/MacOS/Jingli" >> "$TMP/app.log" 2>&1 &
  APP_PID=$!
  for _ in $(seq 1 40); do
    [ -S "$TMP/agent.sock" ] && return 0
    sleep 0.25
  done
  echo "agent socket not created" >&2
  cat "$TMP/app.log" >&2 || true
  exit 1
}

stop_app() {
  if [ -n "$APP_PID" ]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
  fi
  rm -f "$TMP/agent.sock"
}

cleanup() {
  stop_app
  rm -rf "$TMP"
}
trap cleanup EXIT

json() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"]'"$1"')'
}

wait_finished() {
  for _ in $(seq 1 40); do
    local status
    status="$("$CLI" focus status)"
    if echo "$status" | grep -q '"active":false'; then
      if echo "$status" | grep -q '"completion"'; then
        echo "$status"
        return 0
      fi
    fi
    sleep 0.25
  done
  echo "focus did not finish" >&2
  "$CLI" focus status >&2 || true
  exit 1
}

start_app

"$CLI" project add "工作" > /dev/null
"$CLI" task add "写周报" --project 工作 --lane main --date today > /dev/null
"$CLI" task add "回邮件" --lane temporary --date today > /dev/null
A="$("$CLI" task list | python3 -c 'import json,sys; ts=json.load(sys.stdin)["result"]["tasks"]; print(next(t["id"] for t in ts if t["title"]=="写周报"))')"
B="$("$CLI" task list | python3 -c 'import json,sys; ts=json.load(sys.stdin)["result"]["tasks"]; print(next(t["id"] for t in ts if t["title"]=="回邮件"))')"

"$CLI" day plan "$A" "$B" --dry-run | grep -q '"mainCount":1'
"$CLI" day plan "$A" "$B" > /dev/null
"$CLI" day start | grep -q '"dayStarted":true'

"$CLI" focus start "$A" "$B" > "$TMP/first.json"
[ "$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)["result"]["taskIds"]))' < "$TMP/first.json")" = "2" ] || {
  echo "expected 2 shared tasks" >&2
  cat "$TMP/first.json" >&2
  exit 1
}

"$CLI" focus pause | grep -q '"phase":"paused"'
"$CLI" focus resume | grep -q '"phase":"running"'
"$CLI" focus remove "$B" | grep -q "\"taskIds\":\\[\"$A\"\\]"
"$CLI" focus add "$B" > /dev/null

FIRST_FINISH="$(wait_finished)"
python3 - "$FIRST_FINISH" <<'PY'
import json, sys
result = json.loads(sys.argv[1])["result"]
completion = result["completion"]
assert len(completion["taskIds"]) == 2, completion
assert sorted(completion["shares"].values()) == [0.5, 0.5], completion
PY

"$CLI" focus break | grep -q '"onBreak":true'
sleep 1.5
"$CLI" focus status | grep -q '"onBreak":false'

"$CLI" focus start "$A" > /dev/null
wait_finished > /dev/null
"$CLI" focus next > "$TMP/next.json"
grep -q '"active":true' "$TMP/next.json"
wait_finished > /dev/null

"$CLI" stats > "$TMP/stats.json"
python3 - "$TMP/stats.json" <<'PY'
import json, sys
stats = json.load(open(sys.argv[1]))["result"]
assert stats["pomodoros"] == 3, stats
assert stats["focusSeconds"] == 6, stats
assert stats["completedTasks"] == 0, stats
PY

"$CLI" task complete "$B" > /dev/null
"$CLI" stats | python3 -c 'import json,sys; s=json.load(sys.stdin)["result"]; assert s["completedTasks"]==1, s'

"$CLI" day reset --confirm | grep -q '"reset":true'
"$CLI" today | grep -q '"dayStarted":false'

[ -f "$TMP/Backups/jingli-$(date +%F).json" ] || {
  echo "daily backup missing" >&2
  ls -l "$TMP/Backups" >&2 || true
  exit 1
}

grep -q "Jingli Focus On" "$CALLS"
grep -q "Jingli Focus Off" "$CALLS"

stop_app

Y="$(date -v-1d +%F)"
T="$(date +%F)"
sqlite3 "$TMP/jingli.sqlite" "
  UPDATE task SET planned_date='$Y' WHERE done=0;
  INSERT INTO focus_session
    (id, session_date, started_at, duration_sec, status)
  VALUES ('old-session', '$Y', '${Y}T09:00:00Z', 1500, 'completed');
  INSERT OR REPLACE INTO setting (key, value) VALUES ('last_seen_day', '$Y');
"

start_app
sleep 1
sqlite3 "$TMP/jingli.sqlite" "
  SELECT 'old-sessions=' || COUNT(*) FROM focus_session WHERE session_date < '$T';
  SELECT 'today-sessions=' || COUNT(*) FROM focus_session WHERE session_date = '$T';
  SELECT 'open-planned=' || COUNT(*) FROM task WHERE done=0 AND planned_date IS NOT NULL;
  SELECT 'last-seen=' || value FROM setting WHERE key='last_seen_day';
" > "$TMP/rollover.txt"
cat "$TMP/rollover.txt" >&2
grep -q "old-sessions=1" "$TMP/rollover.txt"
grep -q "today-sessions=3" "$TMP/rollover.txt"
grep -q "open-planned=0" "$TMP/rollover.txt"
grep -q "last-seen=$T" "$TMP/rollover.txt"

"$CLI" stats --days 2 > "$TMP/history.json"
python3 - "$TMP/history.json" <<'PY'
import json, sys
days = json.load(open(sys.argv[1]))["result"]["days"]
assert len(days) == 2, days
assert days[0]["pomodoros"] == 3, days[0]
assert days[1]["pomodoros"] == 1, days[1]
PY

echo "dogfood passed: 3 rounds, shared split, pause/resume, add/remove, break, next, stats, reset, backup, rollover, history"
