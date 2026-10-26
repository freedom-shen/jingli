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
                _ = try AppServices.shared.store.updateTask(
                    id: task.id,
                    title: task.title,
                    note: task.note,
                    estimate: 3
                )
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
            case "projects":
                try seedProjects()
                AppServices.shared.model.reload()
                AppServices.shared.model.openProjects()
                captureMainAndPanel(mainPath: mainPath, panelPath: nil)
            case "temporary":
                try seedTemporary()
                AppServices.shared.model.reload()
                AppServices.shared.model.openTemporaryTasks()
                captureMainAndPanel(mainPath: mainPath, panelPath: nil)
            case "task-detail":
                let task = try seedTaskDetail()
                captureTaskDetail(task: task, to: mainPath)
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
                    FloatingPanelView(
                        model: AppServices.shared.model,
                        mode: .standard,
                        onShrink: {},
                        onExpand: {},
                        onClose: {}
                    )
                    .environment(\.controlActiveState, .key)
                    .frame(width: 260, height: 404)
                ),
                size: NSSize(width: 260, height: 404)
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
            onClose: {}
        )
        .environment(\.controlActiveState, .inactive)
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
            lane: "main"
        )
        let temporary = try store.createTask(
            title: "回复客户邮件",
            projectID: project.id,
            lane: "temporary"
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
            lane: "main"
        )
        let second = try store.createTask(
            title: "回复客户邮件",
            projectID: project.id,
            lane: "temporary"
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

    private static func seedProjects() throws {
        let store = AppServices.shared.store

        let older = try store.createProject(
            name: "鸿蒙小程序容器性能优化",
            description: "白屏 · 过渡动画 · 面板跑测",
            color: "sage"
        )
        _ = try store.createTask(title: "增加过渡动画", projectID: older.id, lane: "main")
        _ = try store.createTask(title: "跑一下前 20 的面板", projectID: older.id, lane: "main")

        let newer = try store.createProject(
            name: "鸿蒙问题自动化处理指南",
            description: "提纲 · Skill · 仓库 · demo · 发布",
            color: "rose"
        )
        _ = try store.createTask(title: "确定提纲", projectID: newer.id, lane: "main")

        let middle = try store.createProject(name: "IDE 真机调试支持 Clix", color: "violet")
        _ = try store.createTask(title: "USB 连接尝试简化", projectID: middle.id, lane: "main")

        _ = try store.createProject(name: "旧版容器迁移收尾", color: "slate")

        _ = try store.createTask(title: "临时：回一封邮件", lane: "temporary")
    }

    private static func seedTemporary() throws {
        let store = AppServices.shared.store
        _ = try store.createTask(title: "整理周会材料", lane: "temporary")
        _ = try store.createTask(title: "回一封邮件", lane: "temporary")
        let finished = try store.createTask(title: "已经做完的事", lane: "temporary")
        _ = try store.toggleTask(id: finished.id)
    }

    private static func seedTaskDetail() throws -> Task {
        let task = try AppServices.shared.store.createTask(
            title: "整理季度复盘初稿",
            lane: "temporary",
            estimate: 2
        )
        let updated = try AppServices.shared.store.updateTask(
            id: task.id,
            title: task.title,
            note: """
            把本季度的进展整理成一页复盘：目标、结果、偏差和下一步。

            待办：收集三个方向的产出；对齐时间线；补一版数据对比。

            参考：https://example.com/quarterly-review
            """,
            estimate: 2
        )
        return updated ?? task
    }

    private static func captureTaskDetail(task: Task, to path: String) {
        let view = TaskDetailView(model: AppServices.shared.model, task: task)
            .environment(\.controlActiveState, .inactive)
            .preferredColorScheme(.dark)

        let window = makeWindow(
            rootView: AnyView(view),
            size: NSSize(width: 800, height: 720)
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
