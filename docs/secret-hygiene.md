# 凭证与证书卫生

仓库只放代码。API key、证书、描述文件、`.env` 一律不进 Git，也不进任何设计稿 / 截图 / 日志。

## 已有的防护

| 位置 | 作用 |
|---|---|
| `.gitignore` | `*.p12` `*.p8` `*.mobileprovision` `*.cer` `*.pem` `*.key` `*.jks` `.env` `AuthKey_*.p8` 等 |
| `scripts/check-secrets.sh` | 扫暂存区 / 全仓 / 工作区，命中就退出码 1 |
| `.githooks/pre-commit` | 每次 `git commit` 前自动跑上面那个脚本 |
| `scripts/install-hooks.sh` | 一次性启用钩子（`core.hooksPath` 是本地配置，clone 后要跑一次） |

```bash
scripts/install-hooks.sh     # 装钩子
scripts/check-secrets.sh --all      # 手动全仓体检
```

扫描的特征：OpenCode / OpenAI / GitHub / AWS / Slack 的 key 前缀、`BEGIN … PRIVATE KEY`、
以及 `api_key = "<16+ 字符>"` 这类明文赋值；同时按后缀拦 p12 / mobileprovision / cer / p8 / env。

## Key 到底放在哪

- 本地通道配置：`~/opencode-shen-deepseek.env`（**仓库外**，不随仓库走）。
- `scripts/voice-spike.sh` 只从 `OPENCODE_GO_SHEN_API_KEY` 或那个 env 文件读，不打印、不落盘。
- iOS 端：Key 存 Keychain，不进 UserDefaults、不进备份、不进日志。
- 仓库里只有 `x-opencode-session` 这种**非密钥**的 header 常量。

## 2026-11-17 核对结果

| 检查 | 结果 |
|---|---|
| 已跟踪文件里的 key / 私钥 | 0 命中 |
| 139 条提交历史里的 key / 私钥 | 0 命中 |
| 历史上出现过 p12 / mobileprovision / cer | 0 |
| 设计稿与预览图是否已推到 origin/main | 是（`Design/` + `Design/preview/`，共 10 个文件） |

## 万一泄露

1. **先吊销，再清理**：去后台吊销 key / 撤销证书，别先改历史。
2. 轮换：`~/opencode-shen-deepseek.env` 换新值；iOS 端重新填 Keychain。
3. 清历史：`git filter-repo --path <file> --invert-paths`，然后强推，并让所有 clone 重新拉。
4. 证书类泄露还要检查有没有被用来签别的 App（开发者后台看证书与描述文件）。

## 注意

- 钩子是本地配置：新 clone 的仓库、或者换了机器，都要跑一次 `scripts/install-hooks.sh`。
- 证书和描述文件本来在 `~/Library/...`，不要手动复制进仓库目录。
- 截图和设计稿里不要出现 key 片段——`check-secrets.sh --all` 会扫 HTML/PNG 之外的文本资产。
