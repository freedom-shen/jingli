import Foundation
import JingliCore

/// 助手会话落盘的一条记录。
///
/// 只存回放界面要用的东西：角色、文字、工具名和成败、发出去的图片副本、时间。
/// 不存工具参数和结果——那些是每次重新问模型时现算的。
public struct AssistantHistoryItem: Codable, Sendable, Equatable, Identifiable {
    public struct Tool: Codable, Sendable, Equatable {
        public let name: String
        public let ok: Bool

        public init(name: String, ok: Bool) {
            self.name = name
            self.ok = ok
        }
    }

    /// 存的是发出去那份压过的图（长边 1024 的 JPEG），不是用户原图。
    public struct StoredImage: Codable, Sendable, Equatable {
        public let mimeType: String
        public let base64: String
        public let pixelWidth: Int
        public let pixelHeight: Int

        public init(mimeType: String, base64: String, pixelWidth: Int, pixelHeight: Int) {
            self.mimeType = mimeType
            self.base64 = base64
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }

    public var id: UUID
    /// `user` / `assistant`
    public var role: String
    public var text: String
    public var tools: [Tool]
    public var images: [StoredImage]
    public var at: Date

    public init(
        id: UUID = UUID(),
        role: String,
        text: String,
        tools: [Tool] = [],
        images: [StoredImage] = [],
        at: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.tools = tools
        self.images = images
        self.at = at
    }
}

/// 会话历史文件：默认放 App 支持目录下的 `assistant-history.json`。
///
/// 两端共用：Mac 和 iOS 各自写到自己的支持目录，格式一致。iOS 早期的
/// `chat-history.json` 会被当成旧格式读一次，读到就迁到新文件。
public enum AssistantHistoryStore {
    /// 最多留多少条。
    public static let limit = 120
    /// 文件上限：图片进历史之后，光靠条数兜不住体积。
    public static let maxBytes = 24 * 1024 * 1024

    public static var defaultURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("assistant-history.json")
    }

    public static var legacyURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("chat-history.json")
    }

    public static func load(from url: URL = defaultURL) -> [AssistantHistoryItem] {
        if let items = decode(contentsOf: url) {
            return items
        }
        guard url == defaultURL, let legacy = decodeLegacy(contentsOf: legacyURL) else { return [] }
        // 迁移一次：写成新格式，之后老文件不再读
        save(legacy, to: url)
        return legacy
    }

    public static func save(_ items: [AssistantHistoryItem], to url: URL = defaultURL) {
        var trimmed = Array(items.suffix(limit))
        var data = encode(trimmed)

        // 条数没超但体积超了：从最老的开始丢
        while data.count > maxBytes, trimmed.count > 1 {
            trimmed.removeFirst()
            data = encode(trimmed)
        }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)

        if url == defaultURL {
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    public static func clear(at url: URL = defaultURL) {
        try? FileManager.default.removeItem(at: url)
        if url == defaultURL {
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    public static func byteCount(at url: URL = defaultURL) -> Int {
        (try? Data(contentsOf: url).count) ?? 0
    }

    // MARK: - 图片

    public static func stored(from attachment: ImageAttachment) -> AssistantHistoryItem.StoredImage {
        AssistantHistoryItem.StoredImage(
            mimeType: attachment.mimeType,
            base64: attachment.base64,
            pixelWidth: attachment.pixelWidth,
            pixelHeight: attachment.pixelHeight
        )
    }

    public static func attachment(from stored: AssistantHistoryItem.StoredImage) -> ImageAttachment {
        ImageAttachment(
            mimeType: stored.mimeType,
            base64: stored.base64,
            pixelWidth: stored.pixelWidth,
            pixelHeight: stored.pixelHeight
        )
    }

    // MARK: - 编解码

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func encode(_ items: [AssistantHistoryItem]) -> Data {
        (try? encoder.encode(items)) ?? Data()
    }

    private static func decode(contentsOf url: URL) -> [AssistantHistoryItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([AssistantHistoryItem].self, from: data)
    }

    /// iOS 老文件：没有 images 字段，也没有工具之外的东西。
    private struct LegacyItem: Codable {
        let role: String
        let text: String
        let tools: [AssistantHistoryItem.Tool]
        let at: Date
    }

    private static func decodeLegacy(contentsOf url: URL) -> [AssistantHistoryItem]? {
        guard let data = try? Data(contentsOf: url),
              let items = try? decoder.decode([LegacyItem].self, from: data)
        else { return nil }
        return items.map {
            AssistantHistoryItem(role: $0.role, text: $0.text, tools: $0.tools, images: [], at: $0.at)
        }
    }
}
