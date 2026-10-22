import AppKit
import SwiftUI

@MainActor
enum SnapshotRunner {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.contains("--snapshot") else { return }

        let mainPath = value(for: "--snapshot-out", in: arguments) ?? "/tmp/jingli-snapshot.png"
        let panelPath = value(for: "--snapshot-panel-out", in: arguments)

        let window = snapshotWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        AppServices.shared.model.reload()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let contentView = window.contentView else {
                fputs("snapshot failed: no content view\n", stderr)
                exit(1)
            }

            do {
                contentView.layoutSubtreeIfNeeded()
                try capture(contentView, to: URL(fileURLWithPath: mainPath))
            } catch {
                fputs("snapshot failed: \(error)\n", stderr)
                exit(1)
            }

            guard let panelPath else { exit(0) }

            FloatingPanelController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let panel = NSApp.windows.first(where: { $0 is FloatingPanel }),
                   let panelView = panel.contentView {
                    panelView.layoutSubtreeIfNeeded()
                    try? capture(panelView, to: URL(fileURLWithPath: panelPath))
                }
                exit(0)
            }
        }
    }

    private static func snapshotWindow() -> NSWindow {
        let size = NSSize(width: 1440, height: 900)
        let window = SnapshotWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(
            rootView: RootView()
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        window.setContentSize(size)
        return window
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

private final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

enum SnapshotError: Error {
    case emptyView
    case bitmapCreationFailed
    case pngEncodingFailed
}
