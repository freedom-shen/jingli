#!/usr/bin/env bash
# 装本地 git 钩子（不随 clone 生效，需要每人跑一次）
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
chmod +x .githooks/pre-commit scripts/check-secrets.sh
git config core.hooksPath .githooks
echo "已启用 .githooks（core.hooksPath=$(git config core.hooksPath)）"
