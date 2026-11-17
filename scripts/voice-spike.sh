#!/usr/bin/env bash
# T03 · 语音链路验证：一句话 → 模型 → task.add 参数
#
# 说明：语音转文字由 iOS 系统 Speech 在端上完成（脚本无法在 CI 里开麦克风），
#       所以这里吃的是「已经转写好的那句话」，验证后半段：解析 → 工具调用参数。
#
# 用法：
#   scripts/voice-spike.sh "帮我把评审设计稿加进今天，大概两个钟"
#   OPENCODE_GO_SHEN_API_KEY=xxx scripts/voice-spike.sh "记一下下周一要发版"
#
# Key 只从环境变量或本地 env 文件读，绝不写进仓库、也不回显。

set -euo pipefail

SENTENCE="${1:-帮我把「评审设计稿」加进今天，顺便记一下下周一要发版，大概两个钟}"
BASE="${OPENCODE_GO_SHEN_BASE_URL:-https://opencode.ai/inference/go/openai/v1}"
MODEL="${OPENCODE_GO_SHEN_MODEL:-deepseek-v4.1-flash}"
SESSION="${OPENCODE_GO_SHEN_SESSION:-dsh-opencodego-shen}"

KEY="${OPENCODE_GO_SHEN_API_KEY:-}"
if [ -z "$KEY" ] && [ -f "$HOME/opencode-shen-deepseek.env" ]; then
  # 兼容本地 env 文件（注意：文件里 = 后面可能有空格）
  KEY="$(sed -n 's/^OPENCODE_GO_SHEN_API_KEY=[[:space:]]*//p' "$HOME/opencode-shen-deepseek.env" | head -1 | tr -d '[:space:]')"
fi
if [ -z "$KEY" ]; then
  echo "缺少 OPENCODE_GO_SHEN_API_KEY（或 ~/opencode-shen-deepseek.env）" >&2
  exit 1
fi

TODAY="$(date +%F)"
WEEKDAY="$(date +%u)"

read -r -d '' SYSTEM <<EOF || true
你是「精力管理」的录入助手。今天是 ${TODAY}（周 ${WEEKDAY}）。
把用户口述的一句话拆成 0..n 个任务，调用 task_add。
规则：
- lane 只能是 main 或 temporary；项目里的任务只能是主线，临时任务不能挂项目。
- 用户没说的字段不要猜：estimate 没提就不传；date 没提默认 today。
- 用户只说时长（「两个钟」「一小时」）就换算：25 分钟一个番茄，向上取整（2 小时 ≈ 5）;
- 「下周一」「明天」这类相对日期，换算成 YYYY-MM-DD 再传。
- 一句话里有多件事就调用多次。
EOF

BODY="$(python3 - "$SYSTEM" "$SENTENCE" "$MODEL" <<'PY'
import json, sys
system, sentence, model = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "model": model,
    "messages": [
        {"role": "system", "content": system},
        {"role": "user", "content": sentence},
    ],
    "tools": [{
        "type": "function",
        "function": {
            "name": "task_add",
            "description": "新建任务。临时任务默认进今天；项目任务只进项目，不自动排今天。",
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "maxLength": 160},
                    "lane": {"type": "string", "enum": ["main", "temporary"]},
                    "project": {"type": "string", "description": "项目名称，临时任务不能带"},
                    "date": {"type": "string", "description": "YYYY-MM-DD"},
                    "estimate": {"type": "integer", "minimum": 1, "maximum": 32},
                    "note": {"type": "string", "maxLength": 1000},
                },
                "required": ["title"],
            },
        },
    }],
    "tool_choice": "auto",
    "max_tokens": 400,
}, ensure_ascii=False))
PY
)"

RESP="$(curl -sS -m 45 "$BASE/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -H "x-opencode-session: $SESSION" \
  -H "Content-Type: application/json" \
  --data-binary "$BODY")"

python3 - "$RESP" "$SENTENCE" <<'PY'
import json, sys
raw, sentence = sys.argv[1], sys.argv[2]
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("响应不是 JSON：", raw[:300]); sys.exit(1)
if "error" in data:
    print("接口报错：", json.dumps(data["error"], ensure_ascii=False)); sys.exit(1)
msg = data["choices"][0]["message"]
calls = msg.get("tool_calls") or []
print(f"输入：{sentence}")
print(f"工具调用：{len(calls)} 条")
for c in calls:
    args = json.loads(c["function"]["arguments"])
    print("  -", json.dumps(args, ensure_ascii=False))
if not calls:
    print("  （模型没有调用工具）内容：", (msg.get("content") or "")[:200])
PY
