import AppKit
import SwiftUI
import JingliCore

@MainActor
enum SnapshotRunner {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.contains("--snapshot") else { return }

        let mainPath = value(for: "--snapshot-out", in: arguments) ?? "/tmp/jingli-snapshot.png"
        let panelPath = value(for: "--snapshot-panel-out", in: arguments)
        let fixture = value(for: "--snapshot-fixture", in: arguments) ?? "day-start"

        do {
            switch fixture {
            case "today-running":
                let task = try seedToday()
                AppServices.shared.model.reload()
                AppServices.shared.model.startSnapshotTimer(
                    taskID: task.id,
                    elapsedMs: 12 * 60 * 1000 + 19 * 1000
                )
                captureMainAndPanel(mainPath: mainPath, panelPath: panelPath)
            case "stats":
                try seedStats()
                AppServices.shared.model.reload()
                AppServices.shared.model.openStats()
                captureMainAndPanel(mainPath: mainPath, panelPath: nil)
            case "completion":
                let tasks = try seedCompletionTasks()
                captureCompletion(tasks: tasks, to: mainPath)
            default:
                captureMainAndPanel(mainPath: mainPath, panelPath: panelPath)
            }
        } catch {
            fputs("snapshot failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func captureMainAndPanel(mainPath: String, panelPath: String?) {
        let window = makeWindow(rootView: AnyView(
            RootView()
                .environment(\.controlActiveState, .key)
                .frame(width: 1440, height: 900)
                .preferredColorScheme(.dark)
        ))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

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

            // 用独立窗口渲染浮窗内容，避免受真实面板位置 / 屏幕缩放影响。
            let panelWindow = makeWindow(
                rootView: AnyView(
                    FloatingPanelView(model: AppServices.shared.model, onClose: {})
                        .environment(\.controlActiveState, .key)
                        .frame(width: 260, height: 360)
                ),
                size: NSSize(width: 260, height: 360)
            )
            panelWindow.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let panelView = panelWindow.contentView {
                    panelView.layoutSubtreeIfNeeded()
                    try? capture(panelView, to: URL(fileURLWithPath: panelPath))
                }
                exit(0)
            }
        }
    }

    private static func captureCompletion(tasks: [Task], to path: String) {
        guard tasks.count == 2 else {
            fputs("snapshot failed: completion fixture needs two tasks\n", stderr)
            exit(1)
        }
        let completion = FocusCompletion(
            sessionID: "snapshot",
            taskIDs: tasks.map(\.id),
            shares: [tasks[0].id: 0.5, tasks[1].id: 0.5]
        )
        let view = CompletionOverlay(
            completion: completion,
            tasks: tasks,
            dimmed: false,
            onBreak: {},
            onNextRound: {},
            onClose: {}
        )
        .environment(\.controlActiveState, .key)
        .preferredColorScheme(.dark)

        let window = makeWindow(
            rootView: AnyView(view),
            size: NSSize(width: 460, height: 560)
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let contentView = window.contentView else {
                fputs("snapshot failed: no content view\n", stderr)
                exit(1)
            }
            contentView.layoutSubtreeIfNeeded()
            do {
                try capture(contentView, to: URL(fileURLWithPath: path))
            } catch {
                fputs("snapshot failed: \(error)\n", stderr)
                exit(1)
            }
            exit(0)
        }
    }

    private static func seedToday() throws -> Task {
        let store = AppServices.shared.store
        let today = DayKey.make()
        let project = try store.createProject(name: "工作", description: "本周重点")
        let main = try store.createTask(
            title: "整理产品需求",
            projectID: project.id,
            lane: "main",
            plannedDate: today
        )
        let temporary = try store.createTask(
            title: "回复客户邮件",
            projectID: project.id,
            lane: "temporary",
            plannedDate: today
        )
        try store.startDay(taskIDs: [main.id, temporary.id], today: today)
        return main
    }

    private static func seedStats() throws {
        let store = AppServices.shared.store
        let today = DayKey.make()
        let project = try store.createProject(name: "工作")
        let first = try store.createTask(
            title: "整理产品需求",
            projectID: project.id,
            lane: "main",
            plannedDate: today
        )
        let second = try store.createTask(
            title: "回复客户邮件",
            projectID: project.id,
            lane: "temporary",
            plannedDate: today
        )
        try store.startDay(taskIDs: [first.id, second.id], today: today)
        _ = try store.toggleTask(id: second.id)

        let startedAt = ISO8601DateFormatter().date(from: "2026-10-22T01:30:00Z") ?? Date()
        let startedMs = Int64(startedAt.timeIntervalSince1970 * 1000)
        guard var timer = FocusTimer(
            taskIDs: [first.id, second.id],
            sessionDate: today,
            durationMs: 25 * 60 * 1000
        ) else { return }
        timer.start(now: startedMs, sessionID: "stats-snapshot")
        timer.tick(now: startedMs + Int64(timer.durationMs))
        _ = try FocusTimerStore(database: store.database).complete(timer, now: startedAt)
    }

    private static func seedCompletionTasks() throws -> [Task] {
        let store = AppServices.shared.store
        let project = try store.createProject(name: "工作")
        return [
            try store.createTask(title: "整理产品需求", projectID: project.id, lane: "main"),
            try store.createTask(title: "回复客户邮件", projectID: project.id, lane: "temporary")
        ]
    }

    private static func makeWindow(rootView: AnyView, size: NSSize = NSSize(width: 1440, height: 900)) -> NSWindow {
        let window = SnapshotWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: rootView)
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
