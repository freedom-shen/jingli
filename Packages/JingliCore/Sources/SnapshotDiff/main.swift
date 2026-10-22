import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Options {
    let baseline: String
    let current: String
    let diff: String
    let threshold: Int
    let maxMismatch: Double
}

func parseOptions() -> Options? {
    let args = CommandLine.arguments
    var baseline: String?
    var current: String?
    var diff: String?
    var threshold = 2
    var maxMismatch = 0.003

    var index = 1
    while index < args.count {
        let key = args[index]
        guard index + 1 < args.count else { return nil }
        let value = args[index + 1]
        switch key {
        case "--baseline": baseline = value
        case "--current": current = value
        case "--diff": diff = value
        case "--threshold": threshold = Int(value) ?? threshold
        case "--max-mismatch": maxMismatch = Double(value) ?? maxMismatch
        default: return nil
        }
        index += 2
    }

    guard let baseline, let current, let diff else { return nil }
    return Options(
        baseline: baseline,
        current: current,
        diff: diff,
        threshold: threshold,
        maxMismatch: maxMismatch
    )
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(
        URL(fileURLWithPath: path) as CFURL,
        nil
    ) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func rgbaBytes(_ image: CGImage) -> [UInt8] {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return [] }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}

func makeImage(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

func writePNG(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

func emit(
    status: String,
    mismatch: Double,
    mismatchedPixels: Int,
    totalPixels: Int,
    options: Options,
    message: String? = nil
) {
    var result: [String: Any] = [
        "status": status,
        "mismatch": mismatch,
        "mismatched_pixels": mismatchedPixels,
        "total_pixels": totalPixels,
        "threshold": options.threshold,
        "max_mismatch": options.maxMismatch,
        "baseline": options.baseline,
        "current": options.current,
        "diff": options.diff
    ]
    if let message { result["message"] = message }
    let data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data()
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

guard let options = parseOptions() else {
    fputs("usage: jingli-snapshot-diff --baseline <png> --current <png> --diff <png> [--threshold 2] [--max-mismatch 0.003]\n", stderr)
    exit(2)
}

guard let baseline = loadImage(options.baseline) else {
    emit(status: "failed", mismatch: 1, mismatchedPixels: 0, totalPixels: 0, options: options, message: "cannot load baseline")
    exit(2)
}
guard let current = loadImage(options.current) else {
    emit(status: "failed", mismatch: 1, mismatchedPixels: 0, totalPixels: baseline.width * baseline.height, options: options, message: "cannot load current")
    exit(2)
}

guard baseline.width == current.width, baseline.height == current.height else {
    emit(
        status: "failed",
        mismatch: 1,
        mismatchedPixels: 0,
        totalPixels: baseline.width * baseline.height,
        options: options,
        message: "size mismatch: \(baseline.width)x\(baseline.height) vs \(current.width)x\(current.height)"
    )
    exit(1)
}

let width = baseline.width
let height = baseline.height
let baselineBytes = rgbaBytes(baseline)
let currentBytes = rgbaBytes(current)
guard baselineBytes.count == currentBytes.count, !baselineBytes.isEmpty else {
    emit(status: "failed", mismatch: 1, mismatchedPixels: 0, totalPixels: width * height, options: options, message: "pixel buffer error")
    exit(2)
}

var diffBytes = [UInt8](repeating: 0, count: width * height * 4)
var mismatchedPixels = 0

for pixel in 0..<(width * height) {
    let offset = pixel * 4
    var changed = false
    for channel in 0..<3 {
        let delta = abs(Int(baselineBytes[offset + channel]) - Int(currentBytes[offset + channel]))
        if delta > options.threshold {
            changed = true
        }
    }
    if changed {
        mismatchedPixels += 1
        diffBytes[offset] = 255
        diffBytes[offset + 1] = 0
        diffBytes[offset + 2] = 0
        diffBytes[offset + 3] = 255
    } else {
        diffBytes[offset] = baselineBytes[offset] / 3
        diffBytes[offset + 1] = baselineBytes[offset + 1] / 3
        diffBytes[offset + 2] = baselineBytes[offset + 2] / 3
        diffBytes[offset + 3] = 255
    }
}

let totalPixels = width * height
let mismatch = Double(mismatchedPixels) / Double(totalPixels)
if let diffImage = makeImage(from: diffBytes, width: width, height: height) {
    _ = writePNG(diffImage, to: options.diff)
}

let passed = mismatch <= options.maxMismatch
emit(
    status: passed ? "passed" : "failed",
    mismatch: mismatch,
    mismatchedPixels: mismatchedPixels,
    totalPixels: totalPixels,
    options: options
)
exit(passed ? 0 : 1)
