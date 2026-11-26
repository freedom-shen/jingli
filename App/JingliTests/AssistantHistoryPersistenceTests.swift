import AppKit
import XCTest
import JingliAgent
import JingliCore
@testable import Jingli

/// 会话记录要活过重启：同一个历史文件，换一个模型实例还能读回来。
final class AssistantHistoryPersistenceTests: XCTestCase {
    private var historyURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingli-assistant-history-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: historyURL)
        try super.tearDownWithError()
    }

    @MainActor
    private func makeModel(_ database: JingliDatabase) -> AssistantModel {
        AssistantModel(
            database: database,
            config: LLMConfig(baseURL: "", model: "", session: "", apiKey: ""),
            historyURL: historyURL,
            onChange: {}
        )
    }

    @MainActor
    func testMessageSurvivesNewModelInstance() throws {
        let database = try JingliDatabase.inMemory()
        let first = makeModel(database)
        first.send("把评审设计稿加进今天")

        XCTAssertEqual(first.chat.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))

        let second = makeModel(database)
        XCTAssertEqual(second.chat.count, 2)
        XCTAssertEqual(second.chat.first?.role, .user)
        XCTAssertEqual(second.chat.first?.text, "把评审设计稿加进今天")
        XCTAssertEqual(second.chat.last?.role, .assistant)
        XCTAssertTrue(second.chat.last?.text.contains("还没有配模型") ?? false)
    }

    @MainActor
    func testImagesArePersistedAsTheSentCopy() throws {
        let database = try JingliDatabase.inMemory()
        let png = try Self.makePNG(width: 1200, height: 800)

        let first = makeModel(database)
        first.addImage(data: png)
        XCTAssertEqual(first.attachments.count, 1)
        first.send("")

        let second = makeModel(database)
        let restored = try XCTUnwrap(second.chat.first)
        XCTAssertEqual(restored.role, .user)
        XCTAssertEqual(restored.images.count, 1)
        // 存的是压过的那份，不是 1200 × 800 的原图
        XCTAssertEqual(restored.images.first?.pixelWidth, 1024)
        XCTAssertEqual(restored.images.first?.mimeType, "image/jpeg")
        XCTAssertGreaterThan(restored.images.first?.byteCount ?? 0, 0)
    }

    @MainActor
    func testToolNamesSurviveButArgumentsDoNot() throws {
        let database = try JingliDatabase.inMemory()
        AssistantHistoryStore.save([
            AssistantHistoryItem(
                role: "assistant",
                text: "",
                tools: [.init(name: "today_get", ok: true), .init(name: "task_add", ok: false)],
                at: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ], to: historyURL)

        let model = makeModel(database)
        let restored = try XCTUnwrap(model.chat.first)
        XCTAssertEqual(restored.tools.map(\.name), ["today_get", "task_add"])
        XCTAssertEqual(restored.tools.map(\.ok), [true, false])
        XCTAssertEqual(restored.tools.first?.argumentsJSON, "")
        XCTAssertEqual(restored.tools.first?.output, "")
    }

    @MainActor
    func testClearChatWipesFile() throws {
        let database = try JingliDatabase.inMemory()
        let model = makeModel(database)
        model.send("随便问一句")
        XCTAssertGreaterThan(model.storedHistoryCount, 0)
        XCTAssertGreaterThan(model.storedHistoryBytes, 0)

        model.clearChat()

        XCTAssertTrue(model.chat.isEmpty)
        XCTAssertEqual(model.storedHistoryCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertTrue(makeModel(database).chat.isEmpty)
    }

    @MainActor
    func testHistoryIsCappedAtLimitOnDisk() throws {
        let database = try JingliDatabase.inMemory()
        let items = (0..<(AssistantHistoryStore.limit + 5)).map { index in
            AssistantHistoryItem(role: "user", text: "第 \(index) 条", at: Date())
        }
        AssistantHistoryStore.save(items, to: historyURL)

        let model = makeModel(database)
        XCTAssertEqual(model.chat.count, AssistantHistoryStore.limit)
        XCTAssertEqual(model.chat.last?.text, "第 \(AssistantHistoryStore.limit + 4) 条")
    }

    // MARK: - 帮手

    private static func makePNG(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let buffer = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return buffer as Data
    }
}
