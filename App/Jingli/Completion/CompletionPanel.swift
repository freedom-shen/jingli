import AppKit
import SwiftUI
import JingliCore

final class CompletionPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CompletionPanelController {
    static let shared = CompletionPanelController()

    private var panel: CompletionPanel?

    private init() {}

    func show(
        completion: FocusCompletion,
        tasks: [Task],
        onClose: @escaping () -> Void
    ) {
        hide()

        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = NSSize(width: 460, height: 560)
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        let frame = NSRect(origin: origin, size: size)

        let panel = CompletionPanel(contentRect: frame)
        let content = CompletionOverlay(
            completion: completion,
            tasks: tasks,
            dimmed: false,
            onClose: { [weak self] in
                self?.hide()
                onClose()
            }
        )
        panel.contentView = FirstMouseHostingView(rootView: content)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
