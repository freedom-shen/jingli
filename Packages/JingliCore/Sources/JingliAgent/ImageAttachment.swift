import Foundation

/// 一张要发给模型的图。
///
/// 只存压缩之后的 base64 —— 发出去的是这份缩小过的副本，用户的原图和原文件都不动。
public struct ImageAttachment: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// `image/jpeg` / `image/png`
    public let mimeType: String
    public let base64: String
    /// 压缩后的实际像素，用来在界面上写「2452 × 1536 → 1024 × 642」
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(
        id: UUID = UUID(),
        mimeType: String,
        base64: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.id = id
        self.mimeType = mimeType
        self.base64 = base64
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var data: Data? { Data(base64Encoded: base64) }

    /// OpenAI 兼容接口认的写法：`data:image/jpeg;base64,...`
    public var dataURL: String { "data:\(mimeType);base64,\(base64)" }

    public var byteCount: Int { data?.count ?? 0 }
}
