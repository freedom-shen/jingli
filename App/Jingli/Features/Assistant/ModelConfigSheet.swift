import SwiftUI
import JingliAgent

/// 模型配置：Key 进 Keychain，其余进 UserDefaults；仓库里永远没有密钥。
struct ModelConfigSheet: View {
    @ObservedObject var model: AssistantModel
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var session = ""
    @State private var apiKey = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("模型配置").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 13) {
                field("服务地址", text: $baseURL, prompt: "https://dashscope.aliyuncs.com/compatible-mode/v1", secret: false)
                field("模型名", text: $modelName, prompt: "qwen-vl-max", secret: false)
                field("API Key", text: $apiKey, prompt: "sk-…", secret: true)
                field("额外 Header（可选）", text: $session, prompt: "比如 OpenCode Go 的 x-opencode-session", secret: false)

                Text("只要 OpenAI 兼容的 /chat/completions 都能用：qwen-vl、gpt-4o、DeepSeek、vLLM、Ollama。能不能贴图取决于模型本身；不支持时接口会报错。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                if let testResult {
                    Text(testResult)
                        .font(.system(size: 11))
                        .foregroundStyle(testResult.hasPrefix("连上了") ? Color(red: 0.37, green: 0.75, blue: 0.49) : Theme.tomato)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Divider().overlay(Color.white.opacity(0.07))

            HStack(spacing: 10) {
                Text("Key 存系统 Keychain，其余存 UserDefaults")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary.opacity(0.65))
                Spacer()
                Button(testing ? "测试中…" : "测试连接") {
                    runTest()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(testing)
                .accessibilityIdentifier("model-config-test")

                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)

                Button("保存") {
                    model.updateConfig(LLMConfig(
                        baseURL: baseURL,
                        model: modelName,
                        session: session,
                        apiKey: apiKey
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("model-config-save")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 540)
        .background(Theme.background)
        .onAppear {
            baseURL = model.config.baseURL
            modelName = model.config.model
            session = model.config.session
            apiKey = model.config.apiKey
        }
    }

    private func runTest() {
        let candidate = LLMConfig(baseURL: baseURL, model: modelName, session: session, apiKey: apiKey)
        testing = true
        testResult = nil
        _Concurrency.Task {
            let previous = model.config
            model.updateConfig(candidate)
            let result = await model.testConnection()
            if !result.hasPrefix("连上了") { model.updateConfig(previous) }
            testResult = result
            testing = false
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, secret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary.opacity(0.75))
            Group {
                if secret {
                    SecureField("", text: text, prompt: Text(prompt).foregroundStyle(Theme.textSecondary.opacity(0.5)))
                } else {
                    TextField("", text: text, prompt: Text(prompt).foregroundStyle(Theme.textSecondary.opacity(0.5)))
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08)))
        }
    }
}
