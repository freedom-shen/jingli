import XCTest
@testable import JingliCore
import JingliAgent

private final class ScriptedProvider: ModelProvider, @unchecked Sendable {
    private var responses: [ModelResponse]
    private(set) var seen: [[ChatMessage]] = []

    init(_ responses: [ModelResponse]) { self.responses = responses }

    func complete(messages: [ChatMessage], tools: [ToolSpec]) async throws -> ModelResponse {
        seen.append(messages)
        if responses.isEmpty { return ModelResponse(text: "好的", toolCalls: []) }
        return responses.removeFirst()
    }
}

final class JingliAgentTests: XCTestCase {
    private func makeAgent(_ responses: [ModelResponse]) throws -> (JingliAgent, JingliDatabase, ScriptedProvider) {
        let database = try JingliDatabase.inMemory()
        let router = AgentCommandRouter(database: database, focus: nil, onChange: nil, actor: "test")
        let runner = ToolRunner(router: router)
        let provider = ScriptedProvider(responses)
        let agent = JingliAgent(provider: provider, runner: runner)
        return (agent, database, provider)
    }

    func testCatalogNamesAreUnique() {
        let names = ToolCatalog.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { $0.range(of: "^[a-zA-Z0-9_-]{1,64}$", options: .regularExpression) != nil })
    }

    func testTaskAddToolCreatesTask() async throws {
        let call = ModelToolCall(
            id: "call_1",
            name: "task_add",
            argumentsJSON: #"{"title":"评审设计稿","lane":"temporary","estimate":2}"#
        )
        let (agent, database, _) = try makeAgent([
            ModelResponse(text: nil, toolCalls: [call]),
            ModelResponse(text: "加好了，放在今天的临时任务里。", toolCalls: []),
        ])

        let reply = try await agent.send("帮我把评审设计稿加进今天，2 个番茄")

        XCTAssertEqual(reply.text, "加好了，放在今天的临时任务里。")
        XCTAssertEqual(reply.toolCalls.count, 1)
        XCTAssertTrue(reply.toolCalls[0].ok, "工具应该执行成功：\(reply.toolCalls[0].output)")

        let store = WorkspaceStore(database: database)
        let tasks = try store.listTasks()
        XCTAssertEqual(tasks.map(\.title), ["评审设计稿"])
        XCTAssertEqual(tasks.first?.lane, "temporary")
        XCTAssertEqual(tasks.first?.estimate, 2)
    }

    func testToolFailureIsReportedBackToModel() async throws {
        // 临时任务挂项目 → Core 拒绝
        let call = ModelToolCall(
            id: "call_2",
            name: "task_add",
            argumentsJSON: #"{"title":"不该成功","lane":"temporary","project":"随便"}"#
        )
        let (agent, database, provider) = try makeAgent([
            ModelResponse(text: nil, toolCalls: [call]),
            ModelResponse(text: "临时任务不能挂项目，我改成不挂项目了。", toolCalls: []),
        ])

        let reply = try await agent.send("把这事挂到项目里当临时任务")
        XCTAssertFalse(reply.toolCalls[0].ok)
        XCTAssertTrue(try WorkspaceStore(database: database).listTasks().isEmpty)
        // 失败结果要以 tool 消息回灌给模型
        let last = try XCTUnwrap(provider.seen.last)
        XCTAssertEqual(last.last?.role, .tool)
        XCTAssertTrue(last.last?.content?.contains("error") == true)
    }

    /// 真实模型端到端：没有 JINGLI_LLM_KEY 就跳过（CI 里不会跑）。
    func testRealModelEndToEnd() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["JINGLI_LLM_KEY"], !key.isEmpty else {
            throw XCTSkip("没有 JINGLI_LLM_KEY，跳过真实模型测试")
        }
        let base = env["JINGLI_LLM_BASE"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.deepseek.com/v1")!
        let model = env["JINGLI_LLM_MODEL"] ?? "deepseek-chat"
        var headers: [String: String] = [:]
        if let session = env["JINGLI_LLM_SESSION"], !session.isEmpty {
            headers["x-opencode-session"] = session
        }

        let database = try JingliDatabase.inMemory()
        let router = AgentCommandRouter(database: database, focus: nil, onChange: nil, actor: "test")
        let provider = OpenAICompatibleProvider(config: .init(
            baseURL: base, model: model, apiKey: key, extraHeaders: headers
        ))
        let agent = JingliAgent(provider: provider, runner: ToolRunner(router: router))

        let reply = try await agent.send("帮我加一个临时任务：评审设计稿，大概两个钟")
        XCTAssertTrue(
            reply.toolCalls.contains { $0.name == "task_add" },
            "模型应该调用 task_add，实际：\(reply.toolCalls.map(\.name)) / \(reply.text)"
        )

        let tasks = try WorkspaceStore(database: database).listTasks()
        XCTAssertEqual(tasks.count, 1, "应该只落地一条任务")
        XCTAssertEqual(tasks.first?.title, "评审设计稿")
        XCTAssertEqual(tasks.first?.estimate, 5, "两小时应按 25 分钟向上取整成 5 个番茄")
    }

    func testLoopStopsAfterMaxRounds() async throws {
        let makeCall = { (i: Int) in ModelToolCall(id: "c\(i)", name: "today_get", argumentsJSON: "{}") }
        let responses = (0..<10).map { ModelResponse(text: nil, toolCalls: [makeCall($0)]) }
        let (agent, _, _) = try makeAgent(responses)

        let reply = try await agent.send("一直调工具")
        XCTAssertEqual(reply.toolCalls.count, 4, "最多 4 轮工具调用")
        XCTAssertFalse(reply.text.isEmpty)
    }
}
