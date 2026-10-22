#!/usr/bin/env bash
set -euo pipefail

ON="Jingli Focus On"
OFF="Jingli Focus Off"

if ! shortcuts list | grep -Fxq "$ON" || ! shortcuts list | grep -Fxq "$OFF"; then
  echo "missing shortcuts: $ON / $OFF" >&2
  echo "see docs/focus-shortcuts.md" >&2
  exit 2
fi

shortcuts run "$ON"
sleep 1
shortcuts run "$OFF"
echo "focus spike passed: on -> off"
