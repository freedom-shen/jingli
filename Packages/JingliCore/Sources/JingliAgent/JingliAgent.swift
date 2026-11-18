import Foundation
import JingliCore

public struct ExecutedTool: Sendable, Equatable {
    public let name: String
    public let argumentsJSON: String
    public let ok: Bool
    public let output: String

    public init(name: String, argumentsJSON: String, ok: Bool, output: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.ok = ok
        self.output = output
    }
}

public struct AgentReply: Sendable {
    public let text: String
    public let toolCalls: [ExecutedTool]
    public let messages: [ChatMessage]
}

/// 一次对话 = 模型输出 → 工具调用 → 结果回灌 → 再问，最多 maxRounds 轮。
/// 规则不写在提示词里：4 件主线上限、临时不能挂项目、预估范围都由 router 兜底。
public final class JingliAgent: @unchecked Sendable {
    public static let defaultSystemPrompt = """
    你是「精力管理」的助手。用户用一句话交代今天的事，你调用工具去完成。
    规则：
    - 先读一次 today_get，再决定要不要动今天的计划。
    - 主线任务最多 4 件；临时任务不占名额，但临时任务不能挂项目。
    - 预估只按用户说的填：说「两个钟」按 25 分钟一个番茄向上取整（≈5），没说就不填。
    - 涉及删除这类不可逆操作，先说清楚后果，等用户再确认一次再调用。
    - 回答要短，做完事用一两句话复述结果，不要罗列 JSON。
    """

    private let provider: ModelProvider
    private let runner: ToolRunner
    private let systemPrompt: String
    private let maxRounds: Int

    public init(
        provider: ModelProvider,
        runner: ToolRunner,
        systemPrompt: String = JingliAgent.defaultSystemPrompt,
        maxRounds: Int = 4
    ) {
        self.provider = provider
        self.runner = runner
        self.systemPrompt = systemPrompt
        self.maxRounds = maxRounds
    }

    public func send(_ text: String, history: [ChatMessage] = []) async throws -> AgentReply {
        var messages: [ChatMessage] = [.system(systemPrompt)]
        messages.append(contentsOf: history)
        messages.append(.user(text))

        var executed: [ExecutedTool] = []
        var lastText: String?

        for _ in 0..<maxRounds {
            let response = try await provider.complete(messages: messages, tools: ToolCatalog.all)
            messages.append(.assistant(response.text, calls: response.toolCalls))
            if let text = response.text, !text.isEmpty { lastText = text }

            if response.toolCalls.isEmpty {
                return AgentReply(
                    text: response.text ?? lastText ?? "",
                    toolCalls: executed,
                    messages: messages
                )
            }

            for call in response.toolCalls {
                let outcome = runner.run(name: call.name, argumentsJSON: call.argumentsJSON)
                executed.append(ExecutedTool(
                    name: call.name,
                    argumentsJSON: call.argumentsJSON,
                    ok: outcome.ok,
                    output: outcome.output
                ))
                messages.append(.tool(outcome.output, callID: call.id))
            }
        }

        return AgentReply(
            text: lastText ?? "我试了几轮还没搞定，要不换个说法？",
            toolCalls: executed,
            messages: messages
        )
    }
}
