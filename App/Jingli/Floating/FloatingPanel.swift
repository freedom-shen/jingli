import AppKit
import SwiftUI

enum FloatingPanelConfiguration {
    static let level: NSWindow.Level = .screenSaver
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]
    static let size = NSSize(width: 260, height: 404)
    static let margin: CGFloat = 24
    static let originDefaultsKey = "jingli.floatingPanel.origin"
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
    private var moveObserver: NSObjectProtocol?

    private init() {}

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let frame = NSRect(origin: restoredOrigin(), size: FloatingPanelConfiguration.size)

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

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            MainActor.assumeIsolated {
                FloatingPanelController.shared.persistOrigin(of: panel)
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func restoredOrigin() -> NSPoint {
        let fallback = defaultOrigin()
        guard
            let saved = UserDefaults.standard.array(forKey: FloatingPanelConfiguration.originDefaultsKey),
            saved.count == 2,
            let x = (saved[0] as? NSNumber)?.doubleValue,
            let y = (saved[1] as? NSNumber)?.doubleValue
        else {
            return fallback
        }

        let frame = NSRect(
            origin: NSPoint(x: x, y: y),
            size: FloatingPanelConfiguration.size
        )
        let visible = NSScreen.screens.contains {
            $0.visibleFrame.intersects(frame)
        }
        return visible ? frame.origin : fallback
    }

    private func defaultOrigin() -> NSPoint {
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return NSPoint(
            x: visible.maxX - FloatingPanelConfiguration.size.width - FloatingPanelConfiguration.margin,
            y: visible.minY + FloatingPanelConfiguration.margin
        )
    }

    private func persistOrigin(of panel: NSPanel) {
        guard panel.isVisible else { return }
        UserDefaults.standard.set(
            [panel.frame.origin.x, panel.frame.origin.y],
            forKey: FloatingPanelConfiguration.originDefaultsKey
        )
    }
}
