import XCTest
import JingliAgent

final class AssistantHistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var url: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingli-history-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("assistant-history.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func item(_ text: String, images: [AssistantHistoryItem.StoredImage] = []) -> AssistantHistoryItem {
        AssistantHistoryItem(
            role: "user",
            text: text,
            tools: [.init(name: "task_add", ok: true)],
            images: images,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func image(_ byte: UInt8 = 0x7F) -> AssistantHistoryItem.StoredImage {
        AssistantHistoryItem.StoredImage(
            mimeType: "image/jpeg",
            base64: Data([byte, byte, byte]).base64EncodedString(),
            pixelWidth: 1024,
            pixelHeight: 640
        )
    }

    func testRoundTripKeepsTextToolsImagesAndTime() throws {
        let original = [
            item("把评审设计稿加进今天"),
            AssistantHistoryItem(
                role: "assistant",
                text: "加好了",
                tools: [.init(name: "today_get", ok: true), .init(name: "task_add", ok: false)],
                images: [image()],
                at: Date(timeIntervalSince1970: 1_800_000_100)
            ),
        ]

        AssistantHistoryStore.save(original, to: url)
        let loaded = AssistantHistoryStore.load(from: url)

        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded.last?.images.count, 1)
        XCTAssertEqual(loaded.last?.tools.map(\.name), ["today_get", "task_add"])
        XCTAssertEqual(loaded.last?.tools.last?.ok, false)
    }

    func testKeepsOnlyTheMostRecentLimitItems() {
        let items = (0..<(AssistantHistoryStore.limit + 30)).map { item("第 \($0) 条") }
        AssistantHistoryStore.save(items, to: url)

        let loaded = AssistantHistoryStore.load(from: url)
        XCTAssertEqual(loaded.count, AssistantHistoryStore.limit)
        XCTAssertEqual(loaded.first?.text, "第 30 条")
        XCTAssertEqual(loaded.last?.text, "第 \(AssistantHistoryStore.limit + 29) 条")
    }

    func testOversizedFileDropsOldestUntilItFits() {
        // 一条约 2 MB 的假图，十二条就超过 24 MB 上限
        let blob = String(repeating: "A", count: 2 * 1024 * 1024)
        let bigImage = AssistantHistoryItem.StoredImage(
            mimeType: "image/jpeg", base64: blob, pixelWidth: 1024, pixelHeight: 1024
        )
        let items = (0..<14).map { item("带图第 \($0) 条", images: [bigImage]) }

        AssistantHistoryStore.save(items, to: url)

        let bytes = AssistantHistoryStore.byteCount(at: url)
        XCTAssertLessThanOrEqual(bytes, AssistantHistoryStore.maxBytes)

        let loaded = AssistantHistoryStore.load(from: url)
        XCTAssertLessThan(loaded.count, items.count)
        XCTAssertEqual(loaded.last?.text, "带图第 13 条", "最新的必须留下")
    }

    func testClearRemovesTheFile() {
        AssistantHistoryStore.save([item("x")], to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        AssistantHistoryStore.clear(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(AssistantHistoryStore.load(from: url).isEmpty)
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertTrue(AssistantHistoryStore.load(from: url).isEmpty)
    }

    func testCorruptFileLoadsEmptyInsteadOfCrashing() throws {
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(AssistantHistoryStore.load(from: url).isEmpty)
    }

    func testImageAttachmentRoundTripsThroughStoredImage() {
        let attachment = ImageAttachment(
            mimeType: "image/jpeg",
            base64: Data([1, 2, 3]).base64EncodedString(),
            pixelWidth: 1024,
            pixelHeight: 768
        )
        let restored = AssistantHistoryStore.attachment(from: AssistantHistoryStore.stored(from: attachment))
        XCTAssertEqual(restored.mimeType, attachment.mimeType)
        XCTAssertEqual(restored.base64, attachment.base64)
        XCTAssertEqual(restored.pixelWidth, 1024)
        XCTAssertEqual(restored.pixelHeight, 768)
    }
}
