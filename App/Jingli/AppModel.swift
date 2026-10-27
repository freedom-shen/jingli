import AppKit
import Foundation
import JingliCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: TodaySnapshot?
    @Published var selected: Set<String> = []
    @Published var errorMessage: String?
    @Published var isTaskEditorPresented = false
    @Published var page: AppPage = .day
    @Published var isProjectEditorPresented = false
    @Published var editingProject: Project?
    @Published var taskEditorProjectID: String?
    @Published var taskEditorLane: String?
    @Published private(set) var timer: FocusTimer?
    @Published private(set) var timerText = "25:00"
    @Published private(set) var isOnBreak = false
    @Published private(set) var breakText = FocusTimer.format(AppModel.shortBreakMinutes * 60 * 1000)
    @Published private(set) var consecutiveCompletions = 0
    @Published var completion: FocusCompletion?
    @Published private(set) var lastRoundTaskIDs: [String]
    @Published private(set) var creditTotals: [String: Double] = [:]
    @Published private(set) var projectTaskCounts: [String: Int] = [:]
    /// 今天已完成（收工）的番茄数，浮窗待机态用。
    @Published private(set) var todayPomodoroCount = 0
    @Published var detailTask: Task?
    @Published private(set) var stats: TodayStats?
    @Published var isCommandBarPresented = false
    @Published var commandText = ""
    @Published var commandMessage: String?

    private static let lastRoundDefaultsKey = "jingli.lastRoundTaskIDs"
    private static let streakSettingKey = "focus_streak"
    static let longBreakMinutes = 25
    private static let shortBreakMinutes = 5

    private let store: WorkspaceStore
    private let timerStore: FocusTimerStore
    private let focusMode = FocusModeCoordinator.shared
    private var breakEndsAt: Int64 = 0
    private var streak: FocusStreak
    /// 第 4 个连续钟已完成、等待下一次休息：那次休息升级为 25 分钟长休。
    private var longBreakPending = false
    private var currentDay = DayKey.make()
    private var tickTimer: Timer?
    private var activityToken: NSObjectProtocol?

    init(store: WorkspaceStore = AppServices.shared.store) {
        self.store = store
        self.timerStore = FocusTimerStore(database: store.database)
        self.lastRoundTaskIDs = AppDefaults.current
            .stringArray(forKey: Self.lastRoundDefaultsKey) ?? []
        let persistedStreak = (try? store.settingValue(Self.streakSettingKey))
            .flatMap(Int.init) ?? 0
        self.streak = FocusStreak(count: persistedStreak)
        self.consecutiveCompletions = streak.count
        self.timer = try? timerStore.loadActive()
        restoreFocusMode()
        updateTimerText()
        reload()
        syncActivity()
    }

    var dayStarted: Bool {
        snapshot?.dayStarted ?? false
    }

    var isBusy: Bool {
        timerIsActive || isOnBreak
    }

    /// 待机：今天已经收过番茄，但当前没在计时、也不在休息。
    var isStandby: Bool {
        FocusStandby.isStandby(
            timerActive: timerIsActive,
            onBreak: isOnBreak,
            todayPomodoros: todayPomodoroCount
        )
    }

    var displayText: String {
        isOnBreak ? breakText : timerText
    }

    /// 休息时长（分钟）：连续 4 个钟后升级为长休。
    var breakMinutes: Int {
        breakDurationMs / 60_000
    }

    /// 迷你浮窗的进度环：剩余时间占整轮的比例（0…1）。
    var panelProgress: Double {
        if isOnBreak {
            guard breakEndsAt > 0, breakDurationMs > 0 else { return 0 }
            let remaining = Double(breakEndsAt - nowMilliseconds())
            return max(0, min(1, remaining / Double(breakDurationMs)))
        }
        guard let timer, timer.isActive, timer.durationMs > 0 else { return 0 }
        let remaining = Double(timer.remaining(now: nowMilliseconds()))
        return max(0, min(1, remaining / Double(timer.durationMs)))
    }

    var projects: [Project] {
        (snapshot?.projects ?? []).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.sortOrder > rhs.sortOrder
        }
    }

    var selectedMainCount: Int {
        guard let snapshot else { return 0 }
        let mainIDs = Set(
            snapshot.groups
                .flatMap(\.tasks)
                .filter { $0.lane == "main" }
                .map(\.id)
        )
        return selected.intersection(mainIDs).count
    }

    var selectedTemporaryCount: Int {
        selected.count - selectedMainCount
    }

    func reload() {
        do {
            try store.rolloverIfNeeded()
            let next = try store.snapshot()
            snapshot = next
            creditTotals = (try? store.creditTotals(today: DayKey.make())) ?? [:]
            todayPomodoroCount = (try? store.todayStats().pomodoros) ?? 0
            let allTasks = (try? store.listTasks(includeDone: true)) ?? []
            projectTaskCounts = Dictionary(grouping: allTasks, by: { $0.projectID ?? "" })
                .mapValues(\.count)
            if next.dayStarted {
                selected = []
            } else {
                selected = Set(next.selection)
            }
            if case let .project(id) = page,
               !next.projects.contains(where: { $0.id == id }) {
                page = .projects
            }
            if page == .stats {
                refreshStats()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSelection(_ task: Task) {
        if selected.contains(task.id) {
            selected.remove(task.id)
        } else {
            if task.lane == "main", selectedMainCount >= 4 {
                errorMessage = "主线任务最多 4 个"
                return
            }
            selected.insert(task.id)
        }

        do {
            try store.saveDaySelection(taskIDs: Array(selected))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func canSelect(_ task: Task) -> Bool {
        !(task.lane == "main" && selectedMainCount >= 4 && !selected.contains(task.id))
    }

    func startDay() {
        do {
            try store.startDay(taskIDs: Array(selected))
            reload()
            if FloatingPanelController.shared.hasEverOpened {
                FloatingPanelController.shared.show()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetDay() {
        skipBreak()
        abandonFocus()
        do {
            try store.resetDay()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleDone(_ task: Task) {
        if !task.done, let timer, timer.taskIDs.contains(task.id) {
            if let updated = timer.removingTask(task.id) {
                self.timer = updated
                persistTimer()
                updateTimerText()
            } else {
                abandonFocus()
            }
        }

        do {
            try store.toggleTask(id: task.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openTaskDetail(_ task: Task) {
        detailTask = task
    }

    func closeTaskDetail() {
        detailTask = nil
    }

    @discardableResult
    func updateTask(id: String, title: String, note: String, estimate: Int?) -> Bool {
        do {
            try store.updateTask(
                id: id,
                title: title,
                note: note,
                estimate: estimate
            )
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleDetailDone() {
        guard let task = detailTask else { return }
        detailTask = nil
        toggleDone(task)
    }

    func creditedPomodoros(for task: Task) -> Double {
        creditTotals[task.id] ?? 0
    }

    /// 今天所有任务的预计番茄总数（没估的不计）。
    var todayEstimateTotal: Int {
        (snapshot?.todayTasks ?? []).reduce(0) { $0 + ($1.estimate ?? 0) }
    }

    func projectName(for task: Task) -> String {
        guard let id = task.projectID else { return "无项目" }
        return projects.first { $0.id == id }?.name ?? "无项目"
    }

    /// 任务所属项目名；没有项目时返回 nil，卡片上回退到 lane 标签。
    func assignedProjectName(for task: Task) -> String? {
        guard let id = task.projectID else { return nil }
        return projects.first { $0.id == id }?.name
    }

    @discardableResult
    func createTask(
        title: String,
        lane: String,
        projectID: String?,
        estimate: Int? = nil
    ) -> Bool {
        do {
            try store.createTask(
                title: title,
                projectID: projectID,
                lane: lane,
                plannedDate: (dayStarted && lane == "temporary") ? DayKey.make() : nil,
                estimate: estimate
            )
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func focusState(for task: Task) -> TaskFocusState {
        guard let timer, timer.taskIDs.contains(task.id) else { return .none }
        return timer.phase == .paused ? .paused : .running
    }

    var timerIsActive: Bool {
        timer?.isActive ?? false
    }

    var timerIsPaused: Bool {
        timer?.phase == .paused
    }

    var activeTaskIDs: Set<String> {
        Set(timer?.taskIDs ?? [])
    }

    func startFocus(_ task: Task) {
        if isOnBreak {
            skipBreak()
        }
        longBreakPending = false

        if completion != nil {
            CompletionPanelController.shared.hide()
            completion = nil
        }

        if var current = timer, current.isActive {
            guard !current.taskIDs.contains(task.id) else { return }
            current = current.addingTask(task.id)
            timer = current
            persistTimer()
            updateTimerText()
            return
        }

        startFocus(taskIDs: [task.id])
    }

    func startFocus(taskIDs: [String]) {
        if isOnBreak {
            skipBreak()
        }
        longBreakPending = false

        if completion != nil {
            CompletionPanelController.shared.hide()
            completion = nil
        }

        guard !timerIsActive else { return }
        guard var next = FocusTimer(
            taskIDs: taskIDs,
            sessionDate: DayKey.make(),
            durationMs: timerDurationMs
        ) else { return }
        next.start(now: nowMilliseconds(), sessionID: UUID().uuidString)
        let outcome = beginFocusMode()
        next.setFocusMode(on: outcome == .enabled, owned: outcome == .enabled)
        timer = next
        persistTimer()
        persistFocusOwnership()
        updateTimerText()
        CompletionNotifier.shared.requestAuthorization()
    }

    var lastRoundTasks: [Task] {
        let byID = Dictionary(
            (snapshot?.todayTasks ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return lastRoundTaskIDs.compactMap { byID[$0] }.filter { !$0.done }
    }

    func removeFromLastRound(_ taskID: String) {
        lastRoundTaskIDs.removeAll { $0 == taskID }
        persistLastRound()
    }

    func continueLastRound() {
        let ids = lastRoundTasks.map(\.id)
        guard !ids.isEmpty else { return }
        startFocus(taskIDs: ids)
    }

    private func persistLastRound() {
        AppDefaults.current.set(lastRoundTaskIDs, forKey: Self.lastRoundDefaultsKey)
    }

    func canAddToRound(_ task: Task) -> Bool {
        guard let timer, timer.isActive, !isOnBreak else { return false }
        return !timer.taskIDs.contains(task.id)
    }

    func toggleFocus(for task: Task) {
        switch focusState(for: task) {
        case .running:
            pauseFocus()
        case .paused:
            resumeFocus()
        case .none:
            startFocus(task)
        }
    }

    func pauseFocus() {
        guard var current = timer, current.phase == .running else { return }
        current.pause(now: nowMilliseconds())
        timer = current
        persistTimer()
        updateTimerText()
    }

    func resumeFocus() {
        guard var current = timer, current.phase == .paused else { return }
        current.resume(now: nowMilliseconds())
        timer = current
        persistTimer()
        updateTimerText()
    }

    func abandonFocus() {
        timer = nil
        try? timerStore.clearActive()
        streak = streak.reset()
        persistStreak()
        focusMode.end()
        persistFocusOwnership()
        updateTimerText()
    }

    /// 计时刷新挂在 App 级：主窗口关掉后倒计时与结算仍然继续。
    func startTicking() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickFocus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func tickFocus() {
        syncActivity()
        rolloverIfDayChanged()
        if isOnBreak {
            tickBreak()
            return
        }
        guard var current = timer else { return }
        current.tick(now: nowMilliseconds())
        timer = current
        updateTimerText()
        if current.isFinished {
            finish(current)
        }
    }

    private func rolloverIfDayChanged() {
        let today = DayKey.make()
        guard today != currentDay else { return }
        currentDay = today
        streak = streak.reset()
        persistStreak()
        longBreakPending = false
        reload()
    }

    func startBreak() {
        CompletionPanelController.shared.hide()
        completion = nil
        focusMode.end()
        persistFocusOwnership()
        reload()
        isOnBreak = true
        breakEndsAt = nowMilliseconds() + Int64(breakDurationMs)
        breakText = FocusTimer.format(breakDurationMs)
    }

    func skipBreak() {
        longBreakPending = false
        isOnBreak = false
        breakEndsAt = 0
        breakText = FocusTimer.format(breakDurationMs)
    }

    /// 计时期间持有活动断言，避免 App Nap 在后台节流定时器。
    private func syncActivity() {
        let shouldHold = timerIsActive || isOnBreak
        if shouldHold, activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated],
                reason: "番茄钟计时"
            )
        } else if !shouldHold, let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    private func tickBreak() {
        let remaining = max(0, Int(breakEndsAt - nowMilliseconds()))
        breakText = FocusTimer.format(remaining)
        guard remaining == 0 else { return }
        longBreakPending = false
        isOnBreak = false
        breakEndsAt = 0
        breakText = FocusTimer.format(breakDurationMs)
        CompletionNotifier.shared.notify(
            title: "休息结束",
            body: "可以开始下一轮了"
        )
    }

    /// 回到清单：关掉完成面板后，把主窗口（今天清单）带到前台并激活。
    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first(where: {
                !($0 is FloatingPanel) && !($0 is CompletionPanel)
            })?
            .makeKeyAndOrderFront(nil)
    }

    func dismissCompletion() {
        CompletionPanelController.shared.hide()
        completion = nil
        reload()
        openMainWindow()
    }

    private func finish(_ finished: FocusTimer) {
        lastRoundTaskIDs = finished.taskIDs
        persistLastRound()
        let outcome = streak.completed()
        streak = outcome.streak
        persistStreak()
        longBreakPending = outcome.earnedLongBreak
        let tasks = snapshot?.todayTasks ?? []
        do {
            completion = try timerStore.complete(finished)
            if let completion {
                CompletionPanelController.shared.show(
                    completion: completion,
                    tasks: tasks,
                    longBreak: longBreakPending,
                    onBreak: { [weak self] in
                        self?.startBreak()
                    },
                    onClose: { [weak self] in
                        self?.dismissCompletion()
                    }
                )
                CompletionNotifier.shared.notify(
                    taskCount: finished.taskIDs.count,
                    durationSeconds: finished.durationMs / 1000,
                    longBreak: longBreakPending
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        timer = nil
        focusMode.end()
        persistFocusOwnership()
        updateTimerText()
        reload()
    }

    private var autoDNDEnabled: Bool {
        AppDefaults.current.object(forKey: "jingli.autoDND") as? Bool ?? true
    }

    private func beginFocusMode() -> FocusStartOutcome {
        autoDNDEnabled ? focusMode.begin() : .unavailable
    }

    private func restoreFocusMode() {
        let persisted = try? store.settingValue("focus_owned")
        if let timer, timer.focusModeOwned {
            focusMode.restore()
            persistFocusOwnership()
        } else if persisted == "1" {
            focusMode.end()
            persistFocusOwnership()
        }
    }

    private func persistFocusOwnership() {
        try? store.setSettingValue(
            "focus_owned",
            focusMode.isOwned ? "1" : nil
        )
    }

    private func persistTimer() {
        do {
            try timerStore.saveActive(timer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistStreak() {
        consecutiveCompletions = streak.count
        try? store.setSettingValue(
            Self.streakSettingKey,
            streak.count > 0 ? String(streak.count) : nil
        )
    }

    private func updateTimerText() {
        guard let timer else {
            timerText = "25:00"
            return
        }
        timerText = FocusTimer.format(timer.remaining(now: nowMilliseconds()))
    }

    private func nowMilliseconds() -> Int64 {
        if let raw = ProcessInfo.processInfo.environment["JINGLI_FAKE_NOW_MS"],
           let fixed = Int64(raw) {
            return fixed
        }
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    private var timerDurationMs: Int {
        if let raw = ProcessInfo.processInfo.environment["JINGLI_TIMER_SECONDS"],
           let seconds = Int(raw), seconds > 0 {
            return seconds * 1000
        }
        return FocusTimer.defaultDurationMs
    }

    private var breakDurationMs: Int {
        if let raw = ProcessInfo.processInfo.environment["JINGLI_BREAK_SECONDS"],
           let seconds = Int(raw), seconds > 0 {
            return seconds * 1000
        }
        return (longBreakPending ? Self.longBreakMinutes : Self.shortBreakMinutes)
            * 60 * 1000
    }

    func openTaskEditor(projectID: String? = nil, lane: String? = nil) {
        taskEditorProjectID = projectID
        taskEditorLane = lane
        isTaskEditorPresented = true
    }

    // MARK: - 添加今日任务

    @Published var isAddTaskPresented = false

    func openAddTask() {
        isAddTaskPresented = true
    }

    /// 「添加今日任务」左栏分组：临时任务 → 各项目 → 未归项目的主线任务。
    /// 只包含未完成且不在今天里的任务。
    func addTaskPickerGroups() -> [AddTaskPickerGroup] {
        guard let snapshot else { return [] }
        let todayIDs = Set(snapshot.todayTasks.map(\.id))
        guard let all = try? store.listTasks(includeDone: false) else { return [] }
        let pool = all.filter { !todayIDs.contains($0.id) }

        var groups: [AddTaskPickerGroup] = []
        let temporary = pool.filter { $0.lane == "temporary" }
        if !temporary.isEmpty {
            groups.append(
                AddTaskPickerGroup(
                    id: "temporary", title: "临时任务", color: nil, tasks: temporary
                )
            )
        }
        for project in snapshot.projects {
            let tasks = pool.filter { $0.lane == "main" && $0.projectID == project.id }
            guard !tasks.isEmpty else { continue }
            groups.append(
                AddTaskPickerGroup(
                    id: project.id, title: project.name, color: project.color, tasks: tasks
                )
            )
        }
        let unassigned = pool.filter { $0.lane == "main" && $0.projectID == nil }
        if !unassigned.isEmpty {
            groups.append(
                AddTaskPickerGroup(
                    id: "unassigned", title: "未归项目", color: "slate", tasks: unassigned
                )
            )
        }
        return groups
    }

    var mainSlotsRemaining: Int {
        let used = (try? store.plannedMainCount()) ?? 0
        return max(0, 4 - used)
    }

    /// 左栏点选：把已有任务挂到今天（不复制，保留 lane 与项目归属）。
    @discardableResult
    func addExistingToToday(_ task: Task) -> Bool {
        do {
            try store.addToToday(taskIDs: [task.id])
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 右栏创建：无项目 = 临时任务；选了项目 = 项目任务（主线，占名额）。
    @discardableResult
    func addNewTaskToToday(title: String, projectID: String?) -> Bool {
        do {
            let task = try store.createTask(
                title: title,
                projectID: projectID,
                lane: projectID == nil ? "temporary" : "main"
            )
            try store.addToToday(taskIDs: [task.id])
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 截图测试专用：不触发勿扰、不做持久化的进行中计时。
    func startSnapshotTimer(taskID: String, elapsedMs: Int64) {
        guard var next = FocusTimer(
            taskIDs: [taskID],
            sessionDate: DayKey.make(),
            durationMs: FocusTimer.defaultDurationMs
        ) else { return }
        next.start(now: nowMilliseconds() - elapsedMs, sessionID: "snapshot")
        timer = next
        updateTimerText()
    }

    func openProjects() {
        page = .projects
    }

    func openStats() {
        page = .stats
        refreshStats()
    }

    func openSettings() {
        page = .settings
    }

    func openCommandBar() {
        commandText = ""
        commandMessage = nil
        isCommandBarPresented = true
    }

    func executeCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if text == "统计" || text == "今天怎么样" {
            isCommandBarPresented = false
            openStats()
            return
        }

        if text.hasPrefix("开始 ") {
            let title = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard let task = (snapshot?.todayTasks ?? []).first(where: {
                !$0.done && $0.title.localizedCaseInsensitiveContains(title)
            }) else {
                commandMessage = "今天的任务里找不到「\(title)」"
                return
            }
            startFocus(task)
            isCommandBarPresented = false
            return
        }

        if text.hasPrefix("新任务 ") {
            let title = String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else {
                commandMessage = "新任务后面要跟标题"
                return
            }
            if createTask(title: title, lane: "main", projectID: nil) {
                isCommandBarPresented = false
            }
            return
        }

        commandMessage = "支持：开始 <任务> / 新任务 <标题> / 统计"
    }

    func runBackupNow() -> URL? {
        try? BackupService(
            database: store.database,
            backupDirectory: AppPaths.backupDirectory
        ).exportJSON()
    }

    func importBackup(from url: URL) -> ImportSummary? {
        guard let summary = try? BackupService(
            database: store.database,
            backupDirectory: AppPaths.backupDirectory
        ).importJSON(from: url) else {
            return nil
        }
        reload()
        return summary
    }

    func latestBackup() -> BackupInfo? {
        try? BackupService(
            database: store.database,
            backupDirectory: AppPaths.backupDirectory
        ).listBackups().first
    }

    func refreshStats() {
        stats = try? store.todayStats()
    }

    func openProject(_ id: String) {
        page = .project(id)
    }

    func openTemporaryTasks() {
        page = .temporaryTasks
    }

    func goBack() {
        switch page {
        case .project, .temporaryTasks:
            page = .projects
        default:
            page = .day
        }
    }

    func currentProject() -> Project? {
        guard case let .project(id) = page else { return nil }
        return projects.first { $0.id == id }
    }

    func projectTasks(_ id: String) -> [Task] {
        (try? store.tasks(projectID: id)) ?? []
    }

    func projectTaskCount(_ id: String) -> Int {
        projectTaskCounts[id] ?? 0
    }

    /// 还有任务的项目；没有任务的归入已完结，沉到列表最后。
    var activeProjects: [Project] {
        projects.filter { projectTaskCount($0.id) > 0 }
    }

    var finishedProjects: [Project] {
        projects.filter { projectTaskCount($0.id) == 0 }
    }

    /// 临时任务：不挂在任何项目下，跨天存在，未完成的排在前面。
    var temporaryTasks: [Task] {
        let all = (try? store.listTasks(includeDone: true)) ?? []
        let temporary = all.filter { $0.lane == "temporary" }
        return temporary.filter { !$0.done } + temporary.filter(\.done)
    }

    var temporaryTaskCount: Int {
        temporaryTasks.count
    }

    func isInToday(_ task: Task) -> Bool {
        snapshot?.todayTasks.contains { $0.id == task.id } ?? false
    }

    @discardableResult
    func deleteTask(_ task: Task) -> Bool {
        if let timer, timer.isActive, timer.taskIDs.contains(task.id) {
            errorMessage = "这件任务正在本轮专注里，结束或废弃本轮后再删除。"
            return false
        }
        do {
            _ = try store.deleteTask(id: task.id)
            if detailTask?.id == task.id {
                detailTask = nil
            }
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openProjectEditor(_ project: Project? = nil) {
        editingProject = project
        isProjectEditorPresented = true
    }

    @discardableResult
    func saveProject(
        name: String,
        description: String,
        color: String,
        projectID: String?
    ) -> Bool {
        do {
            if let projectID {
                _ = try store.updateProject(
                    id: projectID,
                    name: name,
                    description: description,
                    color: color
                )
            } else {
                _ = try store.createProject(
                    name: name,
                    description: description,
                    color: color
                )
            }
            editingProject = nil
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteProject(_ project: Project) {
        do {
            try store.deleteProject(id: project.id)
            editingProject = nil
            page = .projects
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum AppPage: Equatable {
    case day
    case projects
    case project(String)
    case temporaryTasks
    case stats
    case settings
}

enum TaskFocusState {
    case none
    case running
    case paused
}

extension AppModel: FocusAgentHandling {
    func agentFocusStatus() throws -> [String: Any] {
        var payload: [String: Any] = [
            "active": timerIsActive,
            "onBreak": isOnBreak,
            "display": displayText,
            "taskIds": timer?.taskIDs ?? [],
            "consecutiveCompletions": consecutiveCompletions,
            "longBreakPending": longBreakPending,
            "breakMinutes": breakMinutes
        ]
        if let timer {
            payload["phase"] = timer.phase.rawValue
            payload["remainingMs"] = timer.remaining(now: nowMilliseconds())
            payload["sessionDate"] = timer.sessionDate
        } else {
            payload["phase"] = "idle"
            payload["remainingMs"] = 0
        }
        if let completion {
            payload["completion"] = [
                "taskIds": completion.taskIDs,
                "shares": completion.shares
            ]
        }
        return payload
    }

    func agentStartFocus(taskIDs: [String]) throws -> [String: Any] {
        if isOnBreak {
            skipBreak()
        }
        longBreakPending = false
        if timerIsActive {
            throw AgentError.invalidParams("已有进行中的番茄钟，请先 stop 或使用 focus add")
        }
        let tasks = try store.listTasks(includeDone: true)
        let known = Set(tasks.map(\.id))
        let unique = taskIDs.filter { known.contains($0) }
        guard unique.count == taskIDs.count, !unique.isEmpty else {
            throw AgentError.notFound("task IDs \(taskIDs)")
        }
        guard var next = FocusTimer(
            taskIDs: unique,
            sessionDate: DayKey.make(),
            durationMs: timerDurationMs
        ) else {
            throw AgentError.invalidParams("任务列表为空")
        }
        next.start(now: nowMilliseconds(), sessionID: UUID().uuidString)
        let outcome = beginFocusMode()
        next.setFocusMode(on: outcome == .enabled, owned: outcome == .enabled)
        timer = next
        persistTimer()
        persistFocusOwnership()
        updateTimerText()
        CompletionNotifier.shared.requestAuthorization()
        return try agentFocusStatus()
    }

    func agentPauseFocus() throws -> [String: Any] {
        guard timerIsActive, !timerIsPaused else {
            throw AgentError.invalidParams("没有可暂停的番茄钟")
        }
        pauseFocus()
        return try agentFocusStatus()
    }

    func agentResumeFocus() throws -> [String: Any] {
        guard timerIsPaused else {
            throw AgentError.invalidParams("番茄钟不在暂停状态")
        }
        resumeFocus()
        return try agentFocusStatus()
    }

    func agentStopFocus() throws -> [String: Any] {
        guard timerIsActive else {
            throw AgentError.invalidParams("没有进行中的番茄钟")
        }
        abandonFocus()
        return try agentFocusStatus()
    }

    func agentAddFocusTask(taskID: String) throws -> [String: Any] {
        guard var current = timer, current.isActive else {
            throw AgentError.invalidParams("没有进行中的番茄钟")
        }
        guard (try store.listTasks(includeDone: true)).contains(where: { $0.id == taskID }) else {
            throw AgentError.notFound("task \(taskID)")
        }
        current = current.addingTask(taskID)
        timer = current
        persistTimer()
        updateTimerText()
        return try agentFocusStatus()
    }

    func agentStartBreak() throws -> [String: Any] {
        guard completion != nil else {
            throw AgentError.invalidParams("本轮尚未结束")
        }
        startBreak()
        return try agentFocusStatus()
    }

    func agentSkipBreak() throws -> [String: Any] {
        guard isOnBreak else {
            throw AgentError.invalidParams("当前不在休息")
        }
        skipBreak()
        return try agentFocusStatus()
    }

    func agentRemoveFocusTask(taskID: String) throws -> [String: Any] {
        guard let current = timer, current.isActive else {
            throw AgentError.invalidParams("没有进行中的番茄钟")
        }
        guard current.taskIDs.contains(taskID) else {
            throw AgentError.notFound("task \(taskID) 不在本轮")
        }
        if let updated = current.removingTask(taskID) {
            timer = updated
            persistTimer()
            updateTimerText()
        } else {
            abandonFocus()
        }
        return try agentFocusStatus()
    }
}
