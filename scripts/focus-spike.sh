#!/usr/bin/env bash
set -euo pipefail

ON="Jingli Focus On"
OFF="Jingli Focus Off"

if ! shortcuts list | grep -Fxq "$ON" || ! shortcuts list | grep -Fxq "$OFF"; then
  echo "missing shortcuts: $ON / $OFF" >&2
  echo "see docs/focus-shortcuts.md" >&2
  exit 2
fi

count_assertions() {
  python3 - <<'PY'
import json, os
path = os.path.expanduser('~/Library/DoNotDisturb/DB/Assertions.json')
try:
    data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError):
    print(0)
else:
    print(sum(len(store.get('storeAssertionRecords', [])) for store in data.get('data', [])))
PY
}

BEFORE="$(count_assertions)"
if [ "$BEFORE" != "0" ]; then
  echo "已有勿扰 / Focus 处于开启状态，跳过 on/off 测试（避免误关）" >&2
  exit 0
fi

shortcuts run "$ON"
sleep 2
AFTER_ON="$(count_assertions)"
if [ "$AFTER_ON" -lt 1 ]; then
  echo "Focus On 未产生勿扰 assertion" >&2
  exit 1
fi

shortcuts run "$OFF"
sleep 2
AFTER_OFF="$(count_assertions)"
if [ "$AFTER_OFF" != "0" ]; then
  echo "Focus Off 后仍有 $AFTER_OFF 个 assertion" >&2
  exit 1
fi

echo "focus spike passed: on -> $AFTER_ON assertion, off -> 0"
