import SwiftUI
import JingliCore

/// 模型配置：Key 存 Keychain，其余存 UserDefaults。
struct ModelConfigSheet: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var session = ""
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("服务地址", text: $baseURL, prompt: "https://api.deepseek.com/v1", secret: false)
                    field("模型名", text: $modelName, prompt: "deepseek-chat", secret: false)
                    field("API Key", text: $apiKey, prompt: "sk-…", secret: true)
                    field("额外 Header（可选）", text: $session, prompt: "比如 OpenCode Go 的 session", secret: false)

                    Text("Key 存在系统 Keychain 里，不会写进任何配置文件，也不会随项目同步。")
                        .font(.system(size: 11)).foregroundStyle(Tokens.text3)
                        .padding(.horizontal, 4)

                    Button {
                        model.updateLLMConfig(LLMConfig(
                            baseURL: baseURL, model: modelName, session: session, apiKey: apiKey
                        ))
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Tokens.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("modelconfig.save")
                    .padding(.top, 4)
                }
                .padding(.horizontal, 18).padding(.top, 10)
            }
            .background(Tokens.bg)
            .navigationTitle("模型配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(Tokens.text3)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            baseURL = model.llmConfig.baseURL
            modelName = model.llmConfig.model
            session = model.llmConfig.session
            apiKey = model.llmConfig.apiKey
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, secret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Tokens.text3)
            Group {
                if secret {
                    SecureField("", text: text, prompt: Text(prompt).foregroundStyle(Tokens.text3))
                } else {
                    TextField("", text: text, prompt: Text(prompt).foregroundStyle(Tokens.text3))
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(Tokens.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Tokens.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tokens.line))
        }
    }
}
