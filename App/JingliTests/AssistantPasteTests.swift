import AppKit
import XCTest
import JingliAgent
import JingliCore
@testable import Jingli

/// 「输入框能贴图」这件事的可执行版本：剪贴板 → 压缩 → 待发送区。
final class AssistantPasteTests: XCTestCase {

    /// 每个用例一份临时历史文件，别碰真实支持目录。
    private func tempHistoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jingli-test-assistant-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @MainActor
    private func makeModel() throws -> AssistantModel {
        let database = try JingliDatabase.inMemory()
        return AssistantModel(
            database: database,
            config: LLMConfig(baseURL: "https://example.com/v1", model: "test", session: "", apiKey: "k"),
            historyURL: tempHistoryURL(),
            onChange: {}
        )
    }

    @MainActor
    func testPastingScreenshotAddsDownscaledAttachment() throws {
        let model = try makeModel()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jingli-test-paste"))

        let png = try Self.makePNG(width: 2400, height: 1500)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(png, forType: .png))

        XCTAssertTrue(model.pasteFromPasteboard(pasteboard))
        XCTAssertEqual(model.attachments.count, 1)

        let attachment = try XCTUnwrap(model.attachments.first)
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertEqual(attachment.pixelWidth, 1024)
        XCTAssertLessThanOrEqual(max(attachment.pixelWidth, attachment.pixelHeight), ImagePreparer.maxPixelSize)
        XCTAssertNil(model.notice)
    }

    @MainActor
    func testPastingTextDoesNotAddAttachment() throws {
        let model = try makeModel()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jingli-test-paste-text"))
        pasteboard.clearContents()
        pasteboard.setString("随便一段文字", forType: .string)

        XCTAssertFalse(model.pasteFromPasteboard(pasteboard))
        XCTAssertTrue(model.attachments.isEmpty)
        XCTAssertEqual(model.notice, "剪贴板里没有图片")
    }

    @MainActor
    func testFourthImageIsAllowedButFifthIsRejected() throws {
        let model = try makeModel()
        let png = try Self.makePNG(width: 200, height: 200)
        for _ in 0..<AssistantModel.maxImages {
            model.addImage(data: png)
        }
        XCTAssertEqual(model.attachments.count, AssistantModel.maxImages)

        model.addImage(data: png)
        XCTAssertEqual(model.attachments.count, AssistantModel.maxImages)
        XCTAssertNotNil(model.notice)
    }

    @MainActor
    func testBrokenImageKeepsNoticeAndAddsNothing() throws {
        let model = try makeModel()
        model.addImage(data: Data("not an image".utf8))
        XCTAssertTrue(model.attachments.isEmpty)
        XCTAssertEqual(model.notice, ImagePrepareError.unsupported.localizedDescription)
    }

    @MainActor
    func testSendWithoutModelConfiguredExplainsInsteadOfDroppingInput() throws {
        let database = try JingliDatabase.inMemory()
        let model = AssistantModel(
            database: database,
            config: LLMConfig(baseURL: "", model: "", session: "", apiKey: ""),
            historyURL: tempHistoryURL(),
            onChange: {}
        )
        model.send("加一件临时任务")

        XCTAssertEqual(model.chat.count, 2)
        XCTAssertEqual(model.chat.first?.role, .user)
        XCTAssertEqual(model.chat.last?.role, .assistant)
        XCTAssertTrue(model.chat.last?.text.contains("还没有配模型") ?? false)
        XCTAssertFalse(model.busy)
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
        context.setFillColor(CGColor(red: 0.9, green: 0.92, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let buffer = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return buffer as Data
    }
}
