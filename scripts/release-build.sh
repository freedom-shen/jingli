#!/usr/bin/env bash
set -euo pipefail

# 兼容旧入口：Release 构建 + 可选签名 + zip（不安装）。
# 新的打包 / 安装脚本是 scripts/package.sh。
exec "$(cd "$(dirname "$0")" && pwd)/package.sh" --no-install "$@"
