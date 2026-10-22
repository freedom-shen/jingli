import AppKit

@MainActor
enum SnapshotRunner {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.contains("--snapshot") else { return }

        let mainPath = value(for: "--snapshot-out", in: arguments) ?? "/tmp/jingli-snapshot.png"
        let panelPath = value(for: "--snapshot-panel-out", in: arguments)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            do {
                guard let window = NSApp.windows.first(where: {
                    $0.contentView != nil && !($0 is FloatingPanel)
                }), let contentView = window.contentView else {
                    throw SnapshotError.noWindow
                }

                window.setContentSize(NSSize(width: 1440, height: 900))
                contentView.layoutSubtreeIfNeeded()
                try capture(contentView, to: URL(fileURLWithPath: mainPath))

                guard let panelPath else {
                    exit(0)
                }

                FloatingPanelController.shared.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let panel = NSApp.windows.first(where: { $0 is FloatingPanel }),
                       let panelView = panel.contentView {
                        panelView.layoutSubtreeIfNeeded()
                        try? capture(panelView, to: URL(fileURLWithPath: panelPath))
                    }
                    exit(0)
                }
            } catch {
                fputs("snapshot failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func capture(_ view: NSView, to url: URL) throws {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            throw SnapshotError.emptyView
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width),
            pixelsHigh: Int(bounds.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SnapshotError.bitmapCreationFailed
        }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}

enum SnapshotError: Error {
    case noWindow
    case emptyView
    case bitmapCreationFailed
    case pngEncodingFailed
}
