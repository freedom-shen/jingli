import Foundation
import Observation
import JingliCore
import JingliAgent
import ActivityKit

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
    private(set) var projectGroups: [ProjectGroup] = []
    private(set) var today: String = DayKey.make()
    private(set) var timer: FocusTimer?
    private(set) var pendingCompletion: FocusCompletion?
    private(set) var breakEndsAt: Date?
    private(set) var breakMinutes: Int = 0
    var errorText: String?

    // MARK: - 助手

    struct ChatItem: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
        let tools: [ExecutedTool]
    }

    private(set) var chat: [ChatItem] = []
    private(set) var assistantBusy = false
    var llmConfig: LLMConfig = LLMConfigStore.fromEnvironment() ?? LLMConfigStore.load()

    var assistantReady: Bool { llmConfig.isReady }

    var provider: OpenAICompatibleProvider? {
        guard llmConfig.isReady, let url = URL(string: llmConfig.baseURL) else { return nil }
        var headers: [String: String] = [:]
        if !llmConfig.session.isEmpty { headers["x-opencode-session"] = llmConfig.session }
        return OpenAICompatibleProvider(config: .init(
            baseURL: url,
            model: llmConfig.model,
            apiKey: llmConfig.apiKey,
            extraHeaders: headers
        ))
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !assistantBusy else { return }
        chat.append(ChatItem(role: .user, text: trimmed, tools: []))
        assistantBusy = true
        defer { assistantBusy = false }

        guard let provider else {
            chat.append(ChatItem(role: .assistant, text: "还没有配置模型，去「设置 → 助手」填一下 Key。", tools: []))
            return
        }
        let router = AgentCommandRouter(database: database, focus: nil, onChange: nil, actor: "ios-agent")
        let agent = JingliAgent(provider: provider, runner: ToolRunner(router: router))
        do {
            let reply = try await agent.send(trimmed)
            chat.append(ChatItem(role: .assistant, text: reply.text, tools: reply.toolCalls))
            refresh()
        } catch {
            chat.append(ChatItem(role: .assistant, text: "出错了：\(error.localizedDescription)", tools: []))
        }
    }

    func updateLLMConfig(_ config: LLMConfig) {
        llmConfig = config
        LLMConfigStore.save(config)
    }

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
        if CommandLine.arguments.contains("-fasttimer"), timer == nil,
           let first = snapshot?.todayTasks.first(where: { !$0.done && $0.lane == "main" }) {
            startFocus(taskID: first.id, durationMs: 6_000)
        }
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
            let allProjects = try store.listProjects()
            projects = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })
            var groups = allProjects.map { project in
                ProjectGroup(
                    id: project.id,
                    project: project,
                    tasks: (try? store.tasks(projectID: project.id)) ?? []
                )
            }
            let uncategorized = ((try? store.listTasks(includeDone: true)) ?? [])
                .filter { $0.projectID == nil }
            if !uncategorized.isEmpty {
                groups.append(ProjectGroup(id: "uncategorized", project: nil, tasks: uncategorized))
            }
            projectGroups = groups.map { group in
                ProjectGroup(
                    id: group.id,
                    project: group.project,
                    tasks: group.tasks.sorted { lhs, rhs in
                        if lhs.done != rhs.done { return !lhs.done }
                        return lhs.sortOrder < rhs.sortOrder
                    }
                )
            }
            timer = try timerStore.loadActive(today: today)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func createProject(name: String, description: String, color: String) throws {
        _ = try store.createProject(name: name, description: description, color: color)
        refresh()
    }

    @discardableResult
    func createTask(
        title: String,
        projectID: String?,
        lane: String,
        estimate: Int?,
        note: String
    ) throws -> JingliCore.Task {
        let task = try store.createTask(
            title: title,
            projectID: projectID,
            lane: lane,
            plannedDate: nil,
            estimate: estimate
        )
        if !note.isEmpty {
            _ = try store.updateTask(id: task.id, title: task.title, note: note, estimate: estimate)
        }
        refresh()
        return task
    }

    func addToToday(taskIDs: [String]) throws {
        _ = try store.addToToday(taskIDs: taskIDs, today: today)
        refresh()
    }

    @discardableResult
    func updateTask(id: String, title: String, note: String, estimate: Int?) throws -> JingliCore.Task? {
        let updated = try store.updateTask(id: id, title: title, note: note, estimate: estimate)
        refresh()
        return updated
    }

    func deleteTask(id: String) throws {
        _ = try store.deleteTask(id: id)
        refresh()
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

    /// 项目页用：每个项目 + 它的任务（含已完成，未完成排前）。
    struct ProjectGroup: Identifiable {
        let id: String
        let project: Project?
        let tasks: [JingliCore.Task]

        var name: String { project?.name ?? "未分类" }
        var openCount: Int { tasks.filter { !$0.done }.count }
    }

    // MARK: - 计时

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func startFocus(taskID: String, durationMs: Int = FocusTimer.defaultDurationMs) {
        guard timer == nil,
              var newTimer = FocusTimer(taskIDs: [taskID], sessionDate: today, durationMs: durationMs) else { return }
        newTimer.start(now: nowMs(), sessionID: UUID().uuidString)
        timer = newTimer
        try? timerStore.saveActive(newTimer)
        let title = snapshot?.todayTasks.first { $0.id == taskID }?.title ?? "专注"
        NotificationScheduler.cancelBreakEnd()
        _Concurrency.Task { await NotificationScheduler.requestAuthorizationIfNeeded() }
        NotificationScheduler.scheduleFocusEnd(after: durationMs / 1000, taskTitle: title)
        FocusActivityManager.shared.start(
            taskTitle: title,
            taskCount: 1,
            endsAt: Date().addingTimeInterval(TimeInterval(durationMs) / 1000),
            remainingSeconds: durationMs / 1000
        )
    }

    func tick() {
        if let end = breakEndsAt, end <= Date() {
            skipBreak()
        }
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
        NotificationScheduler.cancelFocusEnd()
        FocusActivityManager.shared.update(
            isPaused: true,
            endsAt: Date(),
            remainingSeconds: current.remaining(now: nowMs()) / 1000
        )
    }

    func resumeFocus() {
        guard var current = timer else { return }
        current.resume(now: nowMs())
        timer = current
        try? timerStore.saveActive(current)
        NotificationScheduler.scheduleFocusEnd(
            after: current.remaining(now: nowMs()) / 1000,
            taskTitle: snapshot?.todayTasks.first { $0.id == current.taskIDs.first }?.title ?? "专注"
        )
        FocusActivityManager.shared.update(
            isPaused: false,
            endsAt: Date().addingTimeInterval(TimeInterval(current.remaining(now: nowMs())) / 1000),
            remainingSeconds: current.remaining(now: nowMs()) / 1000
        )
    }

    func finishRound() {
        guard let current = timer else { return }
        if current.isFinished {
            pendingCompletion = try? timerStore.complete(current)
        }
        timer = nil
        try? timerStore.clearActive()
        NotificationScheduler.cancelFocusEnd()
        FocusActivityManager.shared.end()
        refresh()
    }

    // MARK: - 休息

    /// 连续 4 个番茄后下一次休息是长休（25 分钟），否则 5 分钟。
    var longBreakPending: Bool {
        let pomodoros = stats?.pomodoros ?? 0
        return pomodoros > 0 && pomodoros % FocusStreak.threshold == 0
    }

    var isOnBreak: Bool { breakEndsAt != nil }

    var breakRemainingMs: Int {
        guard let breakEndsAt else { return 0 }
        return max(0, Int(breakEndsAt.timeIntervalSinceNow * 1000))
    }

    func startBreak() {
        let minutes = longBreakPending ? 25 : 5
        breakMinutes = minutes
        breakEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        NotificationScheduler.scheduleBreakEnd(after: minutes * 60)
        pendingCompletion = nil
    }

    func skipBreak() {
        breakEndsAt = nil
        NotificationScheduler.cancelBreakEnd()
    }

    func dismissCompletion() {
        pendingCompletion = nil
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
