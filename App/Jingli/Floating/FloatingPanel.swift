import AppKit
import SwiftUI

enum FloatingPanelMode: String {
    case standard
    case mini

    var size: NSSize {
        switch self {
        case .standard: return NSSize(width: 260, height: 404)
        case .mini: return NSSize(width: 96, height: 96)
        }
    }
}

enum FloatingPanelConfiguration {
    static let level: NSWindow.Level = .screenSaver
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]
    static let margin: CGFloat = 24
    static let originDefaultsKey = "jingli.floatingPanel.origin"
    static let visibleDefaultsKey = "jingli.floatingPanel.visible"
    static let everOpenedDefaultsKey = "jingli.floatingPanel.everOpened"
    static let modeDefaultsKey = "jingli.floatingPanel.mode"
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
    private(set) var mode: FloatingPanelMode

    private init() {
        let raw = UserDefaults.standard.string(forKey: FloatingPanelConfiguration.modeDefaultsKey)
        mode = raw.flatMap(FloatingPanelMode.init(rawValue:)) ?? .standard
    }

    var wasVisible: Bool {
        UserDefaults.standard.bool(forKey: FloatingPanelConfiguration.visibleDefaultsKey)
    }

    var hasEverOpened: Bool {
        UserDefaults.standard.bool(forKey: FloatingPanelConfiguration.everOpenedDefaultsKey)
    }

    func show() {
        UserDefaults.standard.set(true, forKey: FloatingPanelConfiguration.visibleDefaultsKey)
        UserDefaults.standard.set(true, forKey: FloatingPanelConfiguration.everOpenedDefaultsKey)

        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let frame = NSRect(origin: restoredOrigin(), size: mode.size)

        let panel = FloatingPanel(contentRect: frame)
        panel.contentView = makeContent()
        panel.hasShadow = mode == .standard
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
        UserDefaults.standard.set(false, forKey: FloatingPanelConfiguration.visibleDefaultsKey)
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    func setMode(_ next: FloatingPanelMode) {
        guard next != mode else { return }
        mode = next
        UserDefaults.standard.set(next.rawValue, forKey: FloatingPanelConfiguration.modeDefaultsKey)

        guard let panel else { return }
        panel.contentView = makeContent()

        var frame = panel.frame
        let top = frame.maxY
        frame.size = next.size
        frame.origin.y = top - next.size.height
        frame = clamped(frame)
        panel.hasShadow = next == .standard
        panel.setFrame(frame, display: true)
        persistOrigin(of: panel)
    }

    func shrink() {
        setMode(.mini)
    }

    func expand() {
        setMode(.standard)
    }

    private func makeContent() -> FirstMouseHostingView<FloatingPanelView> {
        FirstMouseHostingView(
            rootView: FloatingPanelView(
                model: AppServices.shared.model,
                mode: mode,
                onShrink: { [weak self] in self?.shrink() },
                onExpand: { [weak self] in self?.expand() },
                onClose: { [weak self] in self?.hide() }
            )
        )
    }

    private func clamped(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(
            max(result.origin.x, visible.minX),
            max(visible.minX, visible.maxX - result.width)
        )
        result.origin.y = min(
            max(result.origin.y, visible.minY),
            max(visible.minY, visible.maxY - result.height)
        )
        return result
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
            size: mode.size
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
            x: visible.maxX - mode.size.width - FloatingPanelConfiguration.margin,
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
