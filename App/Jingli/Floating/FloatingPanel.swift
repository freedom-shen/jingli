import AppKit
import SwiftUI
import JingliCore

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

    static func originKey(for mode: FloatingPanelMode) -> String {
        "jingli.floatingPanel.origin.\(mode.rawValue)"
    }
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
    private var dragEndMonitors: [Any] = []
    private var isSettling = false
    private(set) var mode: FloatingPanelMode

    private init() {
        let raw = AppDefaults.current.string(forKey: FloatingPanelConfiguration.modeDefaultsKey)
        mode = raw.flatMap(FloatingPanelMode.init(rawValue:)) ?? .standard
    }

    var wasVisible: Bool {
        AppDefaults.current.bool(forKey: FloatingPanelConfiguration.visibleDefaultsKey)
    }

    var hasEverOpened: Bool {
        AppDefaults.current.bool(forKey: FloatingPanelConfiguration.everOpenedDefaultsKey)
    }

    func show() {
        AppDefaults.current.set(true, forKey: FloatingPanelConfiguration.visibleDefaultsKey)
        AppDefaults.current.set(true, forKey: FloatingPanelConfiguration.everOpenedDefaultsKey)

        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let frame = NSRect(origin: restoredOrigin(for: mode), size: mode.size)

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
                let controller = FloatingPanelController.shared
                guard !controller.isSettling else { return }
                controller.persistOrigin(of: panel)
            }
        }

        watchDragEnd(for: panel)
    }

    private func watchDragEnd(for panel: FloatingPanel) {
        stopWatchingDragEnd()
        let handler: (NSEvent) -> Void = { [weak self, weak panel] _ in
            guard let self, let panel else { return }
            self.settle(panel)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp],
            handler: handler
        ) {
            dragEndMonitors.append(global)
        }
        dragEndMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
                handler(event)
                return event
            } as Any
        )
    }

    private func stopWatchingDragEnd() {
        for monitor in dragEndMonitors {
            NSEvent.removeMonitor(monitor)
        }
        dragEndMonitors.removeAll()
    }

    /// 松手归位：超出所在屏幕的可见区域时，动画滑回屏幕内并贴住越过的边。
    private func settle(_ panel: FloatingPanel) {
        let target = clamped(panel.frame)
        guard target != panel.frame else { return }
        isSettling = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isSettling = false
            }
        })
        persist(origin: target.origin)
    }

    func hide() {
        AppDefaults.current.set(false, forKey: FloatingPanelConfiguration.visibleDefaultsKey)
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        stopWatchingDragEnd()
        panel?.orderOut(nil)
        panel = nil
    }

    func setMode(_ next: FloatingPanelMode) {
        guard next != mode else { return }
        mode = next
        AppDefaults.current.set(next.rawValue, forKey: FloatingPanelConfiguration.modeDefaultsKey)

        guard let panel else { return }
        panel.contentView = makeContent()

        // 切换模式时各回各位：小圆盘用记住的位置（默认右下角），大窗用自己的。
        var frame = panel.frame
        frame.size = next.size
        frame.origin = restoredOrigin(for: next)
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

    /// 一轮专注开始时调用：浮窗可见则自动缩成迷你圆盘；
    /// 大窗只由用户点小圆盘放大，不跟随启动状态。
    /// 开始 / 完成 / 休息三个时机都调用 shrinkIfVisible。
    func shrinkIfVisible() {
        guard panel != nil else { return }
        shrink()
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

    /// 以窗口中心点判定所属屏幕；中心落在屏幕缝隙时取交集最大的屏。
    private func clamped(_ frame: NSRect) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        var screen = NSScreen.screens.first { $0.frame.contains(center) }
        if screen == nil {
            var bestArea: CGFloat = 0
            for candidate in NSScreen.screens {
                let area = candidate.frame.intersection(frame).width
                    * candidate.frame.intersection(frame).height
                if area > bestArea {
                    bestArea = area
                    screen = candidate
                }
            }
        }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return frame }
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

    private func restoredOrigin(for mode: FloatingPanelMode) -> NSPoint {
        let fallback = defaultOrigin(for: mode)
        let keys = mode == .standard
            ? [FloatingPanelConfiguration.originKey(for: mode), FloatingPanelConfiguration.originDefaultsKey]
            : [FloatingPanelConfiguration.originKey(for: mode)]

        for key in keys {
            guard
                let saved = AppDefaults.current.array(forKey: key),
                saved.count == 2,
                let x = (saved[0] as? NSNumber)?.doubleValue,
                let y = (saved[1] as? NSNumber)?.doubleValue
            else {
                continue
            }

            let frame = NSRect(
                origin: NSPoint(x: x, y: y),
                size: mode.size
            )
            let visible = NSScreen.screens.contains {
                $0.visibleFrame.intersects(frame)
            }
            if visible { return frame.origin }
        }
        return fallback
    }

    private func defaultOrigin(for mode: FloatingPanelMode) -> NSPoint {
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
        persist(origin: panel.frame.origin)
    }

    private func persist(origin: NSPoint) {
        AppDefaults.current.set(
            [origin.x, origin.y],
            forKey: FloatingPanelConfiguration.originKey(for: mode)
        )
    }
}
