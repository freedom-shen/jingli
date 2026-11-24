#!/usr/bin/env bash
set -euo pipefail

# 给当前 iOS 版本打 tag 并推送（Mac 的 tag 由 scripts/package.sh 自动打）。
#
# iOS 装到真机是手动流程，容易忘 tag；每装一次就补一个：
#   scripts/tag-ios.sh              # HEAD 就是这版 iOS
#   scripts/tag-ios.sh <commit>     # 补打历史版本
#
# 版本号读 iOS/project.yml 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-HEAD}"

VERSION="$(grep -m1 'MARKETING_VERSION: "' "$ROOT/iOS/project.yml" | cut -d'"' -f2)"
BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION: "' "$ROOT/iOS/project.yml" | cut -d'"' -f2)"
[ -n "$VERSION" ] || { echo "读不到 iOS 版本号" >&2; exit 1; }

TAG="v$VERSION"
SHA="$(git -C "$ROOT" rev-parse --short "$TARGET")"

if git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
  echo "tag: $TAG 已存在（$(git -C "$ROOT" rev-parse --short "$TAG^{commit}")），跳过"
else
  git -C "$ROOT" tag -a "$TAG" "$TARGET" -m "Jingli iOS $VERSION ($BUILD)"
  echo "tag: $TAG → $SHA"
fi

if ! git -C "$ROOT" push origin "$TAG" > /dev/null 2>&1; then
  echo "警告: 推送 tag $TAG 失败（本地已创建，稍后手动 git push origin $TAG）" >&2
fi
echo "iOS $VERSION ($BUILD) tagged at $SHA"
