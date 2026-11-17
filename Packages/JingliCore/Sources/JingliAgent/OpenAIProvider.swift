import Foundation

public struct OpenAICompatibleConfig: Sendable {
    public var baseURL: URL
    public var model: String
    public var apiKey: String
    /// 例如 OpenCode Go 需要的 x-opencode-session
    public var extraHeaders: [String: String]

    public init(baseURL: URL, model: String, apiKey: String, extraHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
    }

    /// DeepSeek 官方
    public static func deepSeek(apiKey: String, model: String = "deepseek-chat") -> OpenAICompatibleConfig {
        OpenAICompatibleConfig(
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            model: model,
            apiKey: apiKey
        )
    }
}

/// OpenAI 兼容的 chat/completions（DeepSeek、vLLM、Ollama、OpenCode Go 都是这套）。
public struct OpenAICompatibleProvider: ModelProvider {
    private let config: OpenAICompatibleConfig
    private let session: URLSession

    public init(config: OpenAICompatibleConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func complete(messages: [ChatMessage], tools: [ToolSpec]) async throws -> ModelResponse {
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map(Self.encode),
            "temperature": 0.2,
            "stream": false,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { spec in
                [
                    "type": "function",
                    "function": [
                        "name": spec.name,
                        "description": spec.summary,
                        "parameters": spec.schema,
                    ],
                ]
            }
            body["tool_choice"] = "auto"
        }

        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        for (key, value) in config.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelError.badResponse("没有 HTTP 响应")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ModelError.unauthorised
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else {
            throw ModelError.badResponse(String(data: data, encoding: .utf8)?.prefix(200).description ?? "")
        }

        let text = message["content"] as? String
        let rawCalls = message["tool_calls"] as? [[String: Any]] ?? []
        let calls: [ModelToolCall] = rawCalls.compactMap { item in
            guard let id = item["id"] as? String,
                  let function = item["function"] as? [String: Any],
                  let name = function["name"] as? String
            else { return nil }
            let arguments = function["arguments"] as? String ?? "{}"
            return ModelToolCall(id: id, name: name, argumentsJSON: arguments)
        }
        return ModelResponse(text: text?.isEmpty == true ? nil : text, toolCalls: calls)
    }

    private static func encode(_ message: ChatMessage) -> [String: Any] {
        switch message.role {
        case .system, .user:
            return ["role": message.role.rawValue, "content": message.content ?? ""]
        case .assistant:
            var body: [String: Any] = ["role": "assistant"]
            body["content"] = message.content ?? NSNull()
            if !message.toolCalls.isEmpty {
                body["tool_calls"] = message.toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.argumentsJSON],
                    ]
                }
            }
            return body
        case .tool:
            return [
                "role": "tool",
                "tool_call_id": message.toolCallID ?? "",
                "content": message.content ?? "",
            ]
        }
    }
}
