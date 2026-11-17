#!/usr/bin/env bash
# 提交前扫描：API key、私钥、证书、.env 别进仓库。
#
#   scripts/check-secrets.sh            # 只扫暂存区（pre-commit 钩子用）
#   scripts/check-secrets.sh --all      # 扫所有已跟踪文件
#   scripts/check-secrets.sh --worktree # 扫已跟踪 + 未忽略的新文件
#
# 退出码：0 干净；1 有命中。

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

MODE="${1:---staged}"
case "$MODE" in
  --staged|--all|--worktree) ;;
  *) echo "用法: $0 [--staged|--all|--worktree]" >&2; exit 2 ;;
esac

if [ "$MODE" = "--all" ]; then
  FILES=$(git ls-files)
elif [ "$MODE" = "--worktree" ]; then
  FILES=$(git ls-files --cached --others --exclude-standard)
else
  FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
  if [ -z "$FILES" ]; then
    echo "check-secrets: 暂存区为空，跳过"
    exit 0
  fi
fi

[ -z "$FILES" ] && { echo "check-secrets: 没有要检查的文件"; exit 0; }

fail=0

# 1) 文件名/后缀
blocked=$(printf '%s\n' "$FILES" | grep -iE '\.(p12|pfx|mobileprovision|provisionprofile|cer|pem|key|p8|jks|keystore|env)$|(^|/)\.env(\.|$)|AuthKey_.*\.p8$' || true)
if [ -n "$blocked" ]; then
  echo "✗ 这些文件不该进仓库（证书 / 私钥 / 环境变量）：" >&2
  printf '  %s\n' $blocked >&2
  fail=1
fi

# 2) 内容特征。前缀用字符串拼接，避免本脚本自己命中。
P_OPENCODE="oc""_sk_"
P_OPENAI="s""k-[A-Za-z0-9_-]{20,}"
P_GITHUB="gh""p_[A-Za-z0-9]{20,}"
P_AWS="AK""IA[0-9A-Z]{16}"
P_KEY="-----BEGIN"" .*PRIVATE KEY"
P_SLACK="xo""xb-[A-Za-z0-9-]{10,}"
P_ASSIGN='(api[_-]?key|apikey|secret|access[_-]?token|password)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{16,}'

scan() {
  local pat="$1" label="$2" f hit
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    case "$f" in
      scripts/check-secrets.sh|.githooks/*) continue ;;
    esac
    hit=$(grep -nIE -- "$pat" "$f" 2>/dev/null | head -3 || true)
    if [ -n "$hit" ]; then
      echo "✗ [$label] $f" >&2
      printf '%s\n' "$hit" | sed -E 's/^([0-9]+:).{0,48}.*/  \1（已脱敏）/'
      fail=1
    fi
  done <<< "$FILES"
}

scan "$P_OPENCODE" "OpenCode key"
scan "$P_OPENAI"   "OpenAI 风格 key"
scan "$P_GITHUB"   "GitHub token"
scan "$P_AWS"      "AWS key"
scan "$P_KEY"      "私钥"
scan "$P_SLACK"    "Slack token"
scan "$P_ASSIGN"   "疑似明文凭证赋值"

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'MSG'

拒绝提交。处理办法：
  1. 把凭证挪到仓库外（如 ~/.config/jingli/env），代码里只读环境变量；
  2. 从暂存区撤掉：git restore --staged <file>；
  3. 如果已经提交过，必须立刻去后台吊销/轮换，再清理历史。
MSG
  exit 1
fi

echo "check-secrets: 干净 ✓"
