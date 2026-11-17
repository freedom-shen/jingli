import Foundation
import Observation
import JingliCore

/// iOS 端的应用状态。业务规则全部走 JingliCore，这里只负责「读出来给 UI、写回去刷新」。
@MainActor
@Observable
final class IOSAppModel {
    let database: JingliDatabase
    let store: WorkspaceStore
    let timerStore: FocusTimerStore

    private(set) var snapshot: TodaySnapshot?
    private(set) var stats: TodayStats?
    private(set) var credits: [String: Double] = [:]
    private(set) var projects: [String: Project] = [:]
    private(set) var today: String = DayKey.make()
    private(set) var timer: FocusTimer?
    var errorText: String?

    init() {
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.supportDirectory,
                withIntermediateDirectories: true
            )
            database = try JingliDatabase.onDisk(at: AppPaths.databaseURL)
        } catch {
            database = try! JingliDatabase.inMemory()
            errorText = "数据库打开失败，先用内存库：\(error.localizedDescription)"
        }
        store = WorkspaceStore(database: database)
        timerStore = FocusTimerStore(database: database)
        seedDemoIfNeeded()
        refresh()

        // 截图/联调用：-autofocus 直接起一轮
        if CommandLine.arguments.contains("-autofocus"), timer == nil,
           let first = snapshot?.todayTasks.first(where: { !$0.done && $0.lane == "main" }) {
            startFocus(taskID: first.id)
        }
    }

    func refresh() {
        do {
            today = DayKey.make()
            snapshot = try store.snapshot(today: today)
            stats = try store.todayStats(today: today)
            credits = try store.creditTotals(today: today)
            projects = Dictionary(
                uniqueKeysWithValues: try store.listProjects().map { ($0.id, $0) }
            )
            timer = try timerStore.loadActive(today: today)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func toggle(_ task: JingliCore.Task) {
        do {
            _ = try store.toggleTask(id: task.id)
            refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }

    func startDay(taskIDs: [String]) {
        do {
            try store.startDay(taskIDs: taskIDs, today: today)
            refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - 计时

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func startFocus(taskID: String) {
        guard timer == nil,
              var newTimer = FocusTimer(taskIDs: [taskID], sessionDate: today) else { return }
        newTimer.start(now: nowMs(), sessionID: UUID().uuidString)
        timer = newTimer
        try? timerStore.saveActive(newTimer)
    }

    func tick() {
        guard var current = timer, current.phase == .running else { return }
        current.tick(now: nowMs())
        timer = current
        if current.isFinished { finishRound() }
    }

    func pauseFocus() {
        guard var current = timer else { return }
        current.pause(now: nowMs())
        timer = current
        try? timerStore.saveActive(current)
    }

    func resumeFocus() {
        guard var current = timer else { return }
        current.resume(now: nowMs())
        timer = current
        try? timerStore.saveActive(current)
    }

    func finishRound() {
        guard let current = timer else { return }
        if current.isFinished { _ = try? timerStore.complete(current) }
        timer = nil
        try? timerStore.clearActive()
        refresh()
    }

    // MARK: - Demo 数据（只在 -demo 启动参数下写入一次）

    private func seedDemoIfNeeded() {
        let args = CommandLine.arguments
        let isDemo = args.contains("-demo") || args.contains("-demo-fresh")
        let shouldStartDay = args.contains("-demo") && !args.contains("-demo-fresh")
        guard isDemo, (try? store.taskCount()) == 0 else { return }
        let today = DayKey.make()
        guard let lynx = try? store.createProject(name: "Lynx 支持鸿蒙", color: "blue") else { return }

        let main = [
            try? store.createTask(title: "合并现有代码", projectID: lynx.id, lane: "main", estimate: 3),
            try? store.createTask(title: "自定义组件的调试查看", projectID: lynx.id, lane: "main", estimate: 2),
            try? store.createTask(title: "帮助中心的上线准备", projectID: lynx.id, lane: "main"),
        ].compactMap { $0 }

        let temp = [
            try? store.createTask(title: "TTT 支持业务包绑定，支持最新的 kit", lane: "temporary"),
            try? store.createTask(title: "业务包关联 TTT 插件", lane: "temporary", estimate: 1),
        ].compactMap { $0 }

        guard shouldStartDay else { return }
        try? store.startDay(taskIDs: (main + temp).map(\.id), today: today)

        // 两轮已完成的番茄：第一轮单独，第二轮两件共享
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        complete(taskIDs: [main[0].id], at: now - 3_600_000)
        complete(taskIDs: [main[0].id, main[1].id], at: now - 1_800_000)
        _ = try? store.toggleTask(id: main[2].id)   // 第三件标记完成
    }

    private func complete(taskIDs: [String], at startedMs: Int64) {
        guard var timer = FocusTimer(taskIDs: taskIDs, sessionDate: today) else { return }
        timer.start(now: startedMs, sessionID: UUID().uuidString)
        timer.tick(now: startedMs + Int64(FocusTimer.defaultDurationMs))
        _ = try? timerStore.complete(timer)
    }
}
