import Foundation

public struct ModelToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct ChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case system, user, assistant, tool }

    public let role: Role
    public let content: String?
    public let toolCalls: [ModelToolCall]
    public let toolCallID: String?

    public init(role: Role, content: String?, toolCalls: [ModelToolCall] = [], toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    public static func system(_ text: String) -> ChatMessage { .init(role: .system, content: text) }
    public static func user(_ text: String) -> ChatMessage { .init(role: .user, content: text) }
    public static func assistant(_ text: String?, calls: [ModelToolCall] = []) -> ChatMessage {
        .init(role: .assistant, content: text, toolCalls: calls)
    }
    public static func tool(_ text: String, callID: String) -> ChatMessage {
        .init(role: .tool, content: text, toolCallID: callID)
    }
}

public struct ModelResponse: Sendable {
    public let text: String?
    public let toolCalls: [ModelToolCall]

    public init(text: String?, toolCalls: [ModelToolCall]) {
        self.text = text
        self.toolCalls = toolCalls
    }
}

/// 只负责「一次对话往返」，工具执行和循环在 JingliAgent 里。
public protocol ModelProvider: Sendable {
    func complete(messages: [ChatMessage], tools: [ToolSpec]) async throws -> ModelResponse
}

public enum ModelError: Error, LocalizedError {
    case badResponse(String)
    case unauthorised
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .badResponse(detail): return "模型返回格式不对：\(detail)"
        case .unauthorised: return "模型鉴权失败，检查 Key"
        case let .http(code, body): return "模型接口 \(code)：\(body.prefix(120))"
        }
    }
}
