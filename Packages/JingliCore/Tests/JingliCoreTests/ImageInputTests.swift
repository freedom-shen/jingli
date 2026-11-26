import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import JingliCore
@testable import JingliAgent

final class ImageInputTests: XCTestCase {

    // MARK: - 请求体

    func testUserMessageWithoutImagesStaysPlainText() {
        let body = OpenAICompatibleProvider.requestBody(
            model: "m",
            messages: [.user("今天还剩几件")],
            tools: []
        )
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["content"] as? String, "今天还剩几件")
    }

    func testUserMessageWithImageBecomesTextAndImageParts() {
        let image = ImageAttachment(
            mimeType: "image/jpeg",
            base64: Data([0x01, 0x02]).base64EncodedString(),
            pixelWidth: 1024,
            pixelHeight: 640
        )
        let body = OpenAICompatibleProvider.requestBody(
            model: "m",
            messages: [.user("这个白屏了", images: [image])],
            tools: []
        )
        let messages = body["messages"] as? [[String: Any]]
        let parts = messages?.first?["content"] as? [[String: Any]]

        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?.first?["type"] as? String, "text")
        XCTAssertEqual(parts?.first?["text"] as? String, "这个白屏了")

        XCTAssertEqual(parts?.last?["type"] as? String, "image_url")
        let url = (parts?.last?["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertEqual(url, "data:image/jpeg;base64,\(image.base64)")
    }

    func testImageOnlyMessageSkipsEmptyTextPart() {
        let image = ImageAttachment(
            mimeType: "image/jpeg",
            base64: "AAAA",
            pixelWidth: 8,
            pixelHeight: 8
        )
        let body = OpenAICompatibleProvider.requestBody(
            model: "m",
            messages: [.user("", images: [image])],
            tools: []
        )
        let parts = (body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 1)
        XCTAssertEqual(parts?.first?["type"] as? String, "image_url")
    }

    func testToolMessageKeepsStringContent() {
        let encoded = OpenAICompatibleProvider.encode(.tool("{\"ok\":true}", callID: "c1"))
        XCTAssertEqual(encoded["content"] as? String, "{\"ok\":true}")
        XCTAssertEqual(encoded["tool_call_id"] as? String, "c1")
    }

    // MARK: - 压缩

    func testLargeImageIsDownscaledToLongEdgeLimit() throws {
        let png = try Self.makePNG(width: 3000, height: 1200)
        let prepared = try ImagePreparer.prepare(data: png)

        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertLessThanOrEqual(max(prepared.pixelWidth, prepared.pixelHeight), ImagePreparer.maxPixelSize)
        // 长边 3000 → 1024，短边按同一比例
        XCTAssertEqual(prepared.pixelWidth, 1024)
        XCTAssertEqual(prepared.pixelHeight, 410)
        XCTAssertNotNil(prepared.data)
        XCTAssertGreaterThan(prepared.byteCount, 0)
    }

    func testSmallImageKeepsItsOwnSize() throws {
        let png = try Self.makePNG(width: 320, height: 240)
        let prepared = try ImagePreparer.prepare(data: png)
        XCTAssertEqual(prepared.pixelWidth, 320)
        XCTAssertEqual(prepared.pixelHeight, 240)
    }

    func testOversizedFileIsRejectedWithReadableMessage() {
        let big = Data(count: ImagePreparer.maxBytes + 1)
        XCTAssertThrowsError(try ImagePreparer.prepare(data: big)) { error in
            guard case ImagePrepareError.tooLarge = error else {
                return XCTFail("期望 tooLarge，实际 \(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("10 MB"))
        }
    }

    func testGarbageDataIsRejected() {
        XCTAssertThrowsError(try ImagePreparer.prepare(data: Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? ImagePrepareError, .unsupported)
        }
        XCTAssertThrowsError(try ImagePreparer.prepare(data: Data())) { error in
            XCTAssertEqual(error as? ImagePrepareError, .empty)
        }
    }

    // MARK: - 助手把图带进第一轮

    func testAgentForwardsImagesOnFirstRound() async throws {
        let database = try JingliDatabase.inMemory()
        let router = AgentCommandRouter(database: database, focus: nil, onChange: nil, actor: "test")
        let provider = RecordingProvider()
        let agent = JingliAgent(provider: provider, runner: ToolRunner(router: router))

        let image = ImageAttachment(
            mimeType: "image/jpeg",
            base64: "AAAA",
            pixelWidth: 4,
            pixelHeight: 4
        )
        _ = try await agent.send("看图", images: [image])

        let firstRound = try XCTUnwrap(provider.seen.first)
        let userMessage = try XCTUnwrap(firstRound.last)
        XCTAssertEqual(userMessage.role, .user)
        XCTAssertEqual(userMessage.images.count, 1)
    }

    // MARK: - 帮手

    private final class RecordingProvider: ModelProvider, @unchecked Sendable {
        private(set) var seen: [[ChatMessage]] = []
        func complete(messages: [ChatMessage], tools: [ToolSpec]) async throws -> ModelResponse {
            seen.append(messages)
            return ModelResponse(text: "看到图了", toolCalls: [])
        }
    }

    /// 画一张纯色 PNG 当输入。
    private static func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let buffer = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            buffer, "public.png" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return buffer as Data
    }
}
