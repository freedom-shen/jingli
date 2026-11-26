import XCTest
import JingliAgent
import JingliCore
@testable import Jingli

/// 真连模型的联调用例：默认跳过，只有显式给 key 时才跑。
///
///   JINGLI_LIVE_LLM=1 \
///   JINGLI_LLM_KEY=… JINGLI_LLM_BASE=… JINGLI_LLM_MODEL=… JINGLI_LLM_SESSION=… \
///   xcodebuild -project App/Jingli.xcodeproj -scheme Jingli -destination 'platform=macOS' test \
///     -only-testing:JingliTests/AssistantLiveModelTests
///
/// 跑在内存库上，不会碰真实数据。
final class AssistantLiveModelTests: XCTestCase {
    /// 验证 App 进程真的能读到我写进 Keychain + UserDefaults 的那份配置。
    /// xcodebuild 不会把 shell 环境带进测试进程，用一个标记文件当开关。
    private static var liveEnabled: Bool {
        FileManager.default.fileExists(atPath: "/tmp/jingli-live-llm.on")
    }

    @MainActor
    func testStoredConfigIsReadableFromAppProcess() throws {
        guard Self.liveEnabled else {
            throw XCTSkip("放一个 /tmp/jingli-live-llm.on 再跑（连真模型）")
        }
        let config = LLMConfigStore.load()
        XCTAssertFalse(config.apiKey.isEmpty, "Keychain 里没有 key")
        XCTAssertFalse(config.baseURL.isEmpty)
        XCTAssertFalse(config.model.isEmpty)
        try? """
        baseURL=\(config.baseURL)
        model=\(config.model)
        session=\(config.session)
        apiKey=\(config.apiKey.isEmpty ? "空" : "已读到（\(config.apiKey.count) 字符）")
        """.write(to: URL(fileURLWithPath: "/tmp/jingli-stored-config.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testLiveModelAddsTemporaryTask() async throws {
        guard Self.liveEnabled else {
            throw XCTSkip("放一个 /tmp/jingli-live-llm.on 再跑（连真模型）")
        }
        let config = LLMConfigStore.fromEnvironment() ?? LLMConfigStore.load()
        guard config.isReady else {
            throw XCTSkip("没有可用的模型配置（Keychain / 环境变量都没有 key）")
        }

        let database = try JingliDatabase.inMemory()
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingli-live-assistant.json")
        let model = AssistantModel(
            database: database,
            config: config,
            historyURL: historyURL,
            onChange: {}
        )
        let prompt = "加一件临时任务：助手联调验证，估一个番茄"
        model.send(prompt)

        let deadline = Date().addingTimeInterval(180)
        while model.busy, Date() < deadline {
            try await _Concurrency.Task.sleep(for: .milliseconds(300))
        }

        XCTAssertFalse(model.busy, "模型调用超时（180 秒）")
        let reply = model.chat.last?.text ?? ""
        XCTAssertFalse(reply.contains("出错了"), "模型报错：\(reply)")
        XCTAssertEqual(model.chat.first?.role, .user)
        XCTAssertEqual(model.chat.first?.text, prompt)

        let tasks = try WorkspaceStore(database: database).listTasks(includeDone: true)
        let created = tasks.first { $0.title.contains("助手联调验证") }
        XCTAssertNotNil(created, "助手没把任务加进来。对话：\(model.chat.map(\.text))")
        XCTAssertEqual(created?.lane, "temporary")

        let toolNames = model.chat.flatMap(\.tools).map(\.name)
        XCTAssertFalse(toolNames.isEmpty, "这一轮没有调用任何工具")
        // XCTest 会吞掉 stdout，落到文件里方便回看
        let transcript = """
        模型：\(config.model) @ \(config.baseURL)
        工具：\(toolNames.joined(separator: ", "))
        任务：\(created?.title ?? "nil") / lane=\(created?.lane ?? "-") / estimate=\(created?.estimate.map(String.init) ?? "-")
        回复：\(reply)
        """
        try? transcript.write(to: URL(fileURLWithPath: "/tmp/jingli-live-llm.txt"), atomically: true, encoding: .utf8)
    }
}
