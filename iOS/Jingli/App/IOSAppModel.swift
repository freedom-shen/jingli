import Foundation
import Observation
import JingliCore
import JingliAgent
import ActivityKit
import JingliSync
import CloudKit

/// iOS 端的应用状态。业务规则全部走 JingliCore，这里只负责「读出来给 UI、写回去刷新」。
@MainActor
@Observable
final class IOSAppModel {
    let database: JingliDatabase
    let store: WorkspaceStore
    let syncStore: SyncStore
    private var syncService: SyncService?
    private(set) var syncStatus: SyncService.Status?
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

    private static let breakEndsAtKey = "jingli.ios.break.endsAt"
    private static let breakMinutesKey = "jingli.ios.break.minutes"
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
        persistChatHistory()
        assistantBusy = true
        defer { assistantBusy = false }

        guard let provider else {
            chat.append(ChatItem(role: .assistant, text: "还没有配置模型，去「设置 → 助手」填一下 Key。", tools: []))
            persistChatHistory()
            return
        }
        let router = AgentCommandRouter(database: database, focus: nil, onChange: nil, actor: "ios-agent")
        let agent = JingliAgent(provider: provider, runner: ToolRunner(router: router))
        do {
            let reply = try await agent.send(trimmed)
            chat.append(ChatItem(role: .assistant, text: reply.text, tools: reply.toolCalls))
            persistChatHistory()
            refresh()
            if !reply.toolCalls.isEmpty { noteSyncChange() }
        } catch {
            chat.append(ChatItem(role: .assistant, text: "出错了：\(error.localizedDescription)", tools: []))
            persistChatHistory()
        }
    }

    /// 聊天记录本地持久化：启动时读回来，每次追加后写回。
    private func loadChatHistory() {
        let items = ChatHistoryStore.load()
        guard !items.isEmpty else { return }
        chat = items.map { item in
            ChatItem(
                role: item.role == "user" ? .user : .assistant,
                text: item.text,
                tools: item.tools.map {
                    ExecutedTool(name: $0.name, argumentsJSON: "", ok: $0.ok, output: "")
                }
            )
        }
    }

    private func persistChatHistory() {
        ChatHistoryStore.save(
            chat.map { item in
                ChatHistoryStore.Item(
                    role: item.role == .user ? "user" : "assistant",
                    text: item.text,
                    tools: item.tools.map { ChatHistoryStore.Tool(name: $0.name, ok: $0.ok) },
                    at: Date()
                )
            }
        )
    }

    func clearChatHistory() {
        chat.removeAll()
        ChatHistoryStore.clear()
    }

    /// 本地写入完成后调用：去抖 2 秒再同步。
    func noteSyncChange() {
        let service = syncService
        _Concurrency.Task { await service?.noteLocalChange() }
    }

    func syncNow() async {
        guard let syncService else { return }
        syncStatus = await syncService.syncNow()
    }

    func refreshSyncStatus() async {
        guard let syncService else { return }
        syncStatus = await syncService.status()
    }

    /// 自检用：种数据 → 开启一天 → 起一轮，一次做完（顺序敏感，必须串行）。
    func prepareDayForCheck() async {
        await seedCheckData()
        let ids = Array(((try? store.listTasks()) ?? []).prefix(3).map(\.id))
        if snapshot?.dayStarted != true {
            _ = try? store.saveDaySelection(taskIDs: ids, today: today)
            _ = try? store.startDay(taskIDs: ids, today: today)
        } else if (snapshot?.todayTasks.isEmpty ?? true), !ids.isEmpty {
            _ = try? store.addToToday(taskIDs: ids, today: today)
        }
        refresh()
        if timer == nil, let first = snapshot?.todayTasks.first(where: { !$0.done }) {
            startFocus(taskID: first.id)
        }
        NSLog("[PREP] 任务数=\((try? store.taskCount()) ?? -1) 今天=\(snapshot?.todayTasks.count ?? -1) 计时中=\(timer != nil)")
    }

    /// 真机演示数据（都带 `·演示` 标记，`-cleandemo` 可整组删除）。
    func seedCheckData() async {
        guard ((try? store.listTasks()) ?? []).isEmpty else {
            NSLog("[SEED] 已有数据，跳过")
            return
        }
        let lynx = try? store.createProject(name: "Lynx 支持鸿蒙·演示", description: "", color: "blue")
        let ttt = try? store.createProject(name: "TTT 业务包·演示", description: "", color: "amber")
        _ = try? store.createTask(title: "合并现有代码给鸿蒙·演示", projectID: lynx?.id, lane: "main", estimate: 3)
        _ = try? store.createTask(title: "对齐 TTT 包绑定方案·演示", projectID: ttt?.id, lane: "main", estimate: 2)
        _ = try? store.createTask(title: "补一次回归用例·演示", projectID: ttt?.id, lane: "main", estimate: 1)
        _ = try? store.createTask(title: "回邮件·演示", lane: "temporary")
        refresh()
        noteSyncChange()
        NSLog("[SEED] 演示数据已写入，任务数=\((try? store.taskCount()) ?? -1)")
    }

    /// 删掉 `·演示` 标记的任务与项目。
    func cleanCheckData() async {
        for task in (try? store.listTasks(includeDone: true)) ?? [] where task.title.contains("·演示") {
            _ = try? store.deleteTask(id: task.id)
        }
        for project in (try? store.listProjects()) ?? [] where project.name.contains("·演示") {
            _ = try? store.deleteProject(id: project.id)
        }
        refresh()
        noteSyncChange()
        NSLog("[SEED] 演示数据已清理，任务数=\((try? store.taskCount()) ?? -1)")
    }

    /// 自检用：把现有任务排进今天并开启（跳过点击）。
    func startDayForCheck() async {
        guard let snapshot, !snapshot.dayStarted else { NSLog("[DAY] 已经开启或没有数据"); return }
        let ids = snapshot.todayTasks.isEmpty
            ? Array((try? store.listTasks()) ?? []).prefix(4).map(\.id)
            : snapshot.todayTasks.map(\.id)
        _ = try? store.saveDaySelection(taskIDs: ids, today: today)
        _ = try? store.startDay(taskIDs: ids, today: today)
        noteSyncChange()
        refresh()
        NSLog("[DAY] 已开启，任务数=\(ids.count)")
    }

    /// 清掉自检产生的脏数据（CloudKit 里的 PROBE 记录 + 本地验证任务）。
    func cleanProbeData() async {
        let transport = CloudKitTransport(config: .init(containerIdentifier: CloudKitDiagnostics.containerID))
        do {
            let (changes, _) = try await transport.pull(cursor: nil)
            let probes = changes.filter { $0.deviceID == "PROBE" }
            NSLog("[CLEAN] 远端 PROBE 记录=\(probes.count)")
            if !probes.isEmpty {
                let zoneID = CKRecordZone.ID(zoneName: "JingliZone", ownerName: CKCurrentUserDefaultName)
                let ids = probes.map { CKRecord.ID(recordName: $0.changeID, zoneID: zoneID) }
                let database = CKContainer(identifier: CloudKitDiagnostics.containerID).privateCloudDatabase
                _ = try? await database.modifyRecords(saving: [], deleting: ids, savePolicy: .changedKeys, atomically: false)
                NSLog("[CLEAN] 已删除远端 PROBE 记录")
            }
        } catch {
            NSLog("[CLEAN] 拉取失败: \(error)")
        }
        let junk = ["probe"]
        let junkPrefixes = ["A 端任务", "B 端任务", "接线验证", "真机同步验证"]
        for task in (try? store.listTasks(includeDone: true)) ?? []
        where junk.contains(task.title) || junkPrefixes.contains(where: { task.title.hasPrefix($0) }) {
            _ = try? store.deleteTask(id: task.id)
            NSLog("[CLEAN] 删除本地任务 \(task.title)")
        }
        refresh()
        noteSyncChange()
    }

    /// 自检：用真实 CloudKit 模拟第二台设备（全新的内存库 + 独立 deviceID），
    /// 验证「A 写 → B 收到 → B 写 → A 收到」的双向收敛。
    func testTwoDeviceConvergence() async {
        let stamp = DateFormatter()
        stamp.dateFormat = "HHmmss"
        let tag = stamp.string(from: Date())

        guard let dbB = try? JingliDatabase.inMemory() else { return }
        let storeB = WorkspaceStore(database: dbB)
        let syncB = SyncStore(database: dbB)
        let engineB = SyncEngine(
            store: syncB,
            transport: CloudKitTransport(config: .init(containerIdentifier: CloudKitDiagnostics.containerID))
        )

        // A 写一条并推上去
        let titleA = "A 端任务 \(tag)"
        _ = try? store.createTask(title: titleA, lane: "temporary", plannedDate: today)
        await syncNow()
        NSLog("[TWO] A 已推送，待推送=\(((try? syncStore.pendingCount()) ?? -1))")

        // B 拉取
        do {
            let reportB = try await engineB.syncOnce()
            let tasksB = (try? storeB.listTasks(includeDone: true)) ?? []
            NSLog("[TWO] B pulled=\(reportB.pulled) applied=\(reportB.applied) 任务数=\(tasksB.count) 看到A的=\(tasksB.contains { $0.title == titleA })")

            // B 写一条，A 再拉
            let titleB = "B 端任务 \(tag)"
            _ = try? storeB.createTask(title: titleB, lane: "temporary")
            _ = try await engineB.syncOnce()
            await syncNow()
            let tasksA = (try? store.listTasks(includeDone: true)) ?? []
            NSLog("[TWO] A 看到B的=\(tasksA.contains { $0.title == titleB }) 总任务数=\(tasksA.count)")
        } catch {
            NSLog("[TWO] 失败: \(error)")
        }
    }

    /// 自检：走「本地写入 → noteSyncChange → 去抖 → 推送」这条真实路径。
    func testSyncWiring() async {
        let stamp = DateFormatter()
        stamp.dateFormat = "HHmmss"
        _ = try? store.createTask(title: "接线验证 \(stamp.string(from: Date()))", lane: "temporary", plannedDate: today)
        noteSyncChange()
        NSLog("[WIRE] 写入完成，待推送=\(((try? syncStore.pendingCount()) ?? -1))")
        try? await _Concurrency.Task.sleep(nanoseconds: 8_000_000_000)
        await refreshSyncStatus()
        NSLog("[WIRE] 8 秒后 待推送=\(((try? syncStore.pendingCount()) ?? -1)) 上次同步=\(String(describing: syncStatus?.lastSyncAt)) 错误=\(String(describing: syncStatus?.lastError))")
    }

    /// 真机自检：用真实的库跑一次完整同步（推本地变更 → 拉远端 → 重放）。
    func runCloudKitSync() async {
        let sync = SyncStore(database: database)
        let engine = SyncEngine(
            store: sync,
            transport: CloudKitTransport(config: .init(containerIdentifier: CloudKitDiagnostics.containerID))
        )
        let stamp = DateFormatter()
        stamp.dateFormat = "HHmmss"
        _ = try? store.createTask(title: "真机同步验证 \(stamp.string(from: Date()))", lane: "temporary", plannedDate: today)
        NSLog("[CKS] 已创建一条本地任务用于验证推送")
        NSLog("[CKS] 本地任务数=\(((try? store.taskCount()) ?? -1)) 待推送=\(((try? sync.pendingCount()) ?? -1))")
        do {
            let report = try await engine.syncOnce()
            NSLog("[CKS] pushed=\(report.pushed) pulled=\(report.pulled) applied=\(report.applied) skipped=\(report.skipped) retried=\(report.retried)")
            NSLog("[CKS] 同步后待推送=\(((try? sync.pendingCount()) ?? -1)) 远端记录可拉=\((try await sync.syncCursor()) ?? "nil")")
        } catch {
            NSLog("[CKS] 同步失败: \(error)")
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
        syncStore = SyncStore(database: database)
        syncService = SyncService(
            store: syncStore,
            engine: SyncEngine(
                store: syncStore,
                transport: CloudKitTransport(config: .init(containerIdentifier: CloudKitDiagnostics.containerID))
            ),
            debounceSeconds: 2
        )

        seedDemoIfNeeded()
        restoreBreakIfNeeded()
        refresh()
        loadChatHistory()
        startSyncTimer()

        if CommandLine.arguments.contains("-ckcheck") {
            _Concurrency.Task { await CloudKitDiagnostics.run() }
        }
        // 一次性写入模型配置（Key 从环境变量来，仓库和日志里都没有明文）
        if CommandLine.arguments.contains("-setllm") {
            let env = ProcessInfo.processInfo.environment
            var config = LLMConfigStore.load()
            if let v = env["JINGLI_LLM_BASE_URL"], !v.isEmpty { config.baseURL = v }
            if let v = env["JINGLI_LLM_MODEL"], !v.isEmpty { config.model = v }
            if let v = env["JINGLI_LLM_SESSION"], !v.isEmpty { config.session = v }
            if let v = env["JINGLI_LLM_API_KEY"], !v.isEmpty { config.apiKey = v }
            LLMConfigStore.save(config)
            NSLog("[LLM] 已写入配置 base=\(config.baseURL) model=\(config.model) session=\(config.session) keyLength=\(config.apiKey.count)")
        }

        if CommandLine.arguments.contains("-cksync") {
            _Concurrency.Task { await self.runCloudKitSync() }
        }
        if CommandLine.arguments.contains("-syncwiring") {
            _Concurrency.Task { await self.testSyncWiring() }
        }
        if CommandLine.arguments.contains("-endfocus") {
            timer = nil
            try? timerStore.clearActive()
            NotificationScheduler.cancelFocusEnd()
            FocusActivityManager.shared.end()
            refresh()
            NSLog("[DAY] 已结束本地计时")
        }
        if CommandLine.arguments.contains("-emptytoday") {
            _Concurrency.Task {
                let task = try? self.store.createTask(title: "临时占位", lane: "temporary", plannedDate: self.today)
                _ = try? self.store.startDay(taskIDs: [task?.id].compactMap { $0 }, today: self.today)
                if let id = task?.id { _ = try? self.store.deleteTask(id: id) }
                self.refresh()
            }
        }
        if CommandLine.arguments.contains("-prepareday") {
            _Concurrency.Task { await self.prepareDayForCheck() }
        }
        if CommandLine.arguments.contains("-seedcheck") {
            _Concurrency.Task { await self.seedCheckData() }
        }
        if CommandLine.arguments.contains("-startday") {
            _Concurrency.Task { await self.startDayForCheck() }
        }
        if CommandLine.arguments.contains("-cleandemo") {
            _Concurrency.Task { await self.cleanCheckData() }
        }
        if CommandLine.arguments.contains("-cleanprobe") {
            _Concurrency.Task { await self.cleanProbeData() }
        }
        if CommandLine.arguments.contains("-asrfile") {
            _Concurrency.Task { await SpeechFileCheck.run() }
        }
        if CommandLine.arguments.contains("-cktwodevice") {
            _Concurrency.Task { await self.testTwoDeviceConvergence() }
        }

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
        noteSyncChange()
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
        noteSyncChange()
        return task
    }

    func addToToday(taskIDs: [String]) throws {
        _ = try store.addToToday(taskIDs: taskIDs, today: today)
        refresh()
        noteSyncChange()
    }

    @discardableResult
    func updateTask(id: String, title: String, note: String, estimate: Int?) throws -> JingliCore.Task? {
        let updated = try store.updateTask(id: id, title: title, note: note, estimate: estimate)
        refresh()
        noteSyncChange()
        return updated
    }

    /// 重来今天：任务退回未安排，今日的番茄记录保留。
    func resetDay() {
        try? store.resetDay(today: today)
        refresh()
        noteSyncChange()
    }

    func updateProject(id: String, name: String, description: String, color: String) throws {
        _ = try store.updateProject(id: id, name: name, description: description, color: color)
        refresh()
        noteSyncChange()
    }

    func deleteProject(id: String) throws {
        try store.deleteProject(id: id)
        refresh()
        noteSyncChange()
    }

    func deleteTask(id: String) throws {
        _ = try store.deleteTask(id: id)
        refresh()
        noteSyncChange()
    }

    func toggle(_ task: JingliCore.Task) {
        do {
            _ = try store.toggleTask(id: task.id)
            refresh()
            noteSyncChange()
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

    private var lastSyncTick = Date.distantPast
    private var syncTimer: Timer?

    /// 独立的同步节拍。
    ///
    /// 之前只在专注页的 TimelineView 里跑 tick()，不专心时根本不走，
    /// 结果手机放着不动就永远收不到对端的数据。
    private func startSyncTimer() {
        guard syncTimer == nil else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    /// 每 15 秒最多跑一次：有未推送就推，没有就拉。
    private func syncTick() {
        let now = Date()
        guard now.timeIntervalSince(lastSyncTick) > 15 else { return }
        lastSyncTick = now
        let pending = (try? syncStore.pendingCount()) ?? 0
        if pending > 0 {
            noteSyncChange()
        } else {
            _Concurrency.Task { await syncNow() }
        }
    }

    func tick() {
        syncTick()
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
        noteSyncChange()
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
        // 休息跨进程也要还在：杀进程回来能看到剩余时间
        UserDefaults.standard.set(breakEndsAt, forKey: Self.breakEndsAtKey)
        UserDefaults.standard.set(minutes, forKey: Self.breakMinutesKey)
    }

    func skipBreak() {
        breakEndsAt = nil
        NotificationScheduler.cancelBreakEnd()
        UserDefaults.standard.removeObject(forKey: Self.breakEndsAtKey)
        UserDefaults.standard.removeObject(forKey: Self.breakMinutesKey)
    }

    /// 启动时恢复未结束的休息。
    private func restoreBreakIfNeeded() {
        guard let end = UserDefaults.standard.object(forKey: Self.breakEndsAtKey) as? Date else { return }
        if end > Date() {
            breakEndsAt = end
            breakMinutes = UserDefaults.standard.integer(forKey: Self.breakMinutesKey)
        } else {
            skipBreak()
        }
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
