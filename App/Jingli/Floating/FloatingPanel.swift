import AppKit
import SwiftUI

enum FloatingPanelConfiguration {
    static let level: NSWindow.Level = .screenSaver
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]
    static let size = NSSize(width: 260, height: 360)
    static let margin: CGFloat = 24
}

/// Spike 验证用：把实际窗口层级 / collectionBehavior / frame 写到 JSON。
struct PanelSpikeReport: Codable {
    let level: Int
    let collectionBehavior: UInt
    let frame: [Double]
    let screenFrame: [Double]
    let timestamp: String
}

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = FloatingPanelConfiguration.level
        collectionBehavior = FloatingPanelConfiguration.collectionBehavior
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 保证 App 不在前台时，第一次点击也能命中按钮。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()

    private var panel: FloatingPanel?

    private init() {}

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            writeReport(for: panel)
            return
        }

        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: visible.maxX - FloatingPanelConfiguration.size.width - FloatingPanelConfiguration.margin,
            y: visible.minY + FloatingPanelConfiguration.margin
        )
        let frame = NSRect(origin: origin, size: FloatingPanelConfiguration.size)

        let panel = FloatingPanel(contentRect: frame)
        let content = FloatingPanelView(
            model: AppServices.shared.model,
            onClose: { [weak panel] in
                panel?.orderOut(nil)
            }
        )
        panel.contentView = FirstMouseHostingView(rootView: content)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        writeReport(for: panel)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func writeReport(for panel: NSPanel) {
        let report = PanelSpikeReport(
            level: panel.level.rawValue,
            collectionBehavior: panel.collectionBehavior.rawValue,
            frame: [
                Double(panel.frame.origin.x),
                Double(panel.frame.origin.y),
                Double(panel.frame.size.width),
                Double(panel.frame.size.height)
            ],
            screenFrame: [
                Double(panel.screen?.visibleFrame.origin.x ?? 0),
                Double(panel.screen?.visibleFrame.origin.y ?? 0),
                Double(panel.screen?.visibleFrame.size.width ?? 0),
                Double(panel.screen?.visibleFrame.size.height ?? 0)
            ],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        guard let data = try? JSONEncoder().encode(report) else { return }
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jingli", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("panel-spike.json"))
    }
}
