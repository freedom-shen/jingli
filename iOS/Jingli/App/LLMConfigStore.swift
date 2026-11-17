import Foundation
import Security

struct LLMConfig: Sendable, Equatable {
    var baseURL: String
    var model: String
    var session: String
    var apiKey: String

    static let defaultBase = "https://api.deepseek.com/v1"
    static let defaultModel = "deepseek-chat"

    var isReady: Bool { !apiKey.isEmpty && !baseURL.isEmpty && !model.isEmpty }
}

/// Key 存 Keychain，其余（baseURL / model / session）存 UserDefaults。
/// 仓库里永远没有任何密钥。
enum LLMConfigStore {
    private static let keychainKey = "com.freedom-shen.jingli.llm.apikey"
    private static let baseDefaultsKey = "llm.baseURL"
    private static let modelDefaultsKey = "llm.model"
    private static let sessionDefaultsKey = "llm.session"

    static func load() -> LLMConfig {
        let defaults = UserDefaults.standard
        return LLMConfig(
            baseURL: defaults.string(forKey: baseDefaultsKey) ?? LLMConfig.defaultBase,
            model: defaults.string(forKey: modelDefaultsKey) ?? LLMConfig.defaultModel,
            session: defaults.string(forKey: sessionDefaultsKey) ?? "",
            apiKey: readKeychain() ?? ""
        )
    }

    static func save(_ config: LLMConfig) {
        let defaults = UserDefaults.standard
        defaults.set(config.baseURL, forKey: baseDefaultsKey)
        defaults.set(config.model, forKey: modelDefaultsKey)
        defaults.set(config.session, forKey: sessionDefaultsKey)
        if config.apiKey.isEmpty {
            deleteKeychain()
        } else {
            writeKeychain(config.apiKey)
        }
    }

    /// 调试/联调：用环境变量覆盖，不写进任何存储。
    static func fromEnvironment() -> LLMConfig? {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["JINGLI_LLM_KEY"], !key.isEmpty else { return nil }
        return LLMConfig(
            baseURL: env["JINGLI_LLM_BASE"] ?? LLMConfig.defaultBase,
            model: env["JINGLI_LLM_MODEL"] ?? LLMConfig.defaultModel,
            session: env["JINGLI_LLM_SESSION"] ?? "",
            apiKey: key
        )
    }

    // MARK: - Keychain

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainKey,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var add = query
            add.merge(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
