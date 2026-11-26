import CoreGraphics
import Foundation
import ImageIO

public enum ImagePrepareError: Error, LocalizedError, Equatable {
    case empty
    case unsupported
    case tooLarge(bytes: Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "这张图是空的"
        case .unsupported:
            return "读不出这张图，换一张试试"
        case let .tooLarge(bytes):
            let mb = Double(bytes) / 1024 / 1024
            return "单张上限 \(ImagePreparer.maxBytes / 1024 / 1024) MB，这张 \(String(format: "%.1f", mb)) MB"
        }
    }
}

/// 把图压到能发的大小：长边不超过 1024 px，重编码成 JPEG。
///
/// 只用 CoreGraphics / ImageIO，macOS 和 iOS 同一份代码；不碰用户磁盘上的原图。
public enum ImagePreparer {
    /// 长边上限。再大对模型没帮助，只会让请求变慢变贵。
    public static let maxPixelSize = 1024
    /// 原始文件上限：超过就直接拒，别让 HTTP 卡在那儿传。
    public static let maxBytes = 10 * 1024 * 1024
    public static let jpegQuality = 0.8

    public static func prepare(
        data: Data,
        maxPixelSize: Int = ImagePreparer.maxPixelSize
    ) throws -> ImageAttachment {
        guard !data.isEmpty else { throw ImagePrepareError.empty }
        guard data.count <= maxBytes else { throw ImagePrepareError.tooLarge(bytes: data.count) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw ImagePrepareError.unsupported }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // 跟着 EXIF 转正，否则手机竖拍的截图发过去是躺着的
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImagePrepareError.unsupported
        }

        let jpeg = try encodeJPEG(image)
        return ImageAttachment(
            mimeType: "image/jpeg",
            base64: jpeg.base64EncodedString(),
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }

    public static func prepare(
        contentsOf url: URL,
        maxPixelSize: Int = ImagePreparer.maxPixelSize
    ) throws -> ImageAttachment {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImagePrepareError.unsupported
        }
        return try prepare(data: data, maxPixelSize: maxPixelSize)
    }

    private static func encodeJPEG(_ image: CGImage) throws -> Data {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, "public.jpeg" as CFString, 1, nil
        ) else { throw ImagePrepareError.unsupported }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw ImagePrepareError.unsupported }
        return buffer as Data
    }
}
