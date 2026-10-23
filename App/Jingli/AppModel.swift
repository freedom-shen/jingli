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
    @Published private(set) var breakText = "05:00"
    @Published var completion: FocusCompletion?
    @Published var detailTask: Task?
    @Published private(set) var stats: TodayStats?
    @Published var isCommandBarPresented = false
    @Published var commandText = ""
    @Published var commandMessage: String?

    private let store: WorkspaceStore
    private let timerStore: FocusTimerStore
    private let focusMode = FocusModeCoordinator.shared
    private var breakEndsAt: Int64 = 0
    private var currentDay = DayKey.make()

    init(store: WorkspaceStore = AppServices.shared.store) {
        self.store = store
        self.timerStore = FocusTimerStore(database: store.database)
        self.timer = try? timerStore.loadActive()
        restoreFocusMode()
        updateTimerText()
        reload()
    }

    var dayStarted: Bool {
        snapshot?.dayStarted ?? false
    }

    var isBusy: Bool {
        timerIsActive || isOnBreak
    }

    var displayText: String {
        isOnBreak ? breakText : timerText
    }

    var projects: [Project] {
        snapshot?.projects ?? []
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
    func updateTask(id: String, title: String, note: String) -> Bool {
        do {
            try store.updateTask(id: id, title: title, note: note)
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
        (try? store.creditTotal(taskID: task.id)) ?? 0
    }

    func projectName(for task: Task) -> String {
        guard let id = task.projectID else { return "无项目" }
        return projects.first { $0.id == id }?.name ?? "无项目"
    }

    @discardableResult
    func createTask(title: String, lane: String, projectID: String?) -> Bool {
        do {
            try store.createTask(
                title: title,
                projectID: projectID,
                lane: lane,
                plannedDate: (dayStarted && lane == "temporary") ? DayKey.make() : nil
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

        if var current = timer, current.isActive {
            guard !current.taskIDs.contains(task.id) else { return }
            current = current.addingTask(task.id)
            timer = current
            persistTimer()
            updateTimerText()
            return
        }

        guard var next = FocusTimer(
            taskIDs: [task.id],
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
        focusMode.end()
        persistFocusOwnership()
        updateTimerText()
    }

    func tickFocus() {
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
        isOnBreak = false
        breakEndsAt = 0
        breakText = "05:00"
    }

    func startNextRound() {
        guard let completion else { return }
        let candidates = (snapshot?.todayTasks ?? []).filter {
            !$0.done && completion.taskIDs.contains($0.id)
        }
        CompletionPanelController.shared.hide()
        self.completion = nil
        reload()

        guard let first = candidates.first,
              var next = FocusTimer(
                taskIDs: candidates.map(\.id),
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
        _ = first
    }

    private func tickBreak() {
        let remaining = max(0, Int(breakEndsAt - nowMilliseconds()))
        breakText = FocusTimer.format(remaining)
        guard remaining == 0 else { return }
        isOnBreak = false
        breakEndsAt = 0
        breakText = "05:00"
        CompletionNotifier.shared.notify(
            title: "休息结束",
            body: "可以开始下一轮了"
        )
    }

    func dismissCompletion() {
        CompletionPanelController.shared.hide()
        completion = nil
        reload()
    }

    private func finish(_ finished: FocusTimer) {
        let tasks = snapshot?.todayTasks ?? []
        do {
            completion = try timerStore.complete(finished)
            if let completion {
                CompletionPanelController.shared.show(
                    completion: completion,
                    tasks: tasks,
                    onBreak: { [weak self] in
                        self?.startBreak()
                    },
                    onNextRound: { [weak self] in
                        self?.startNextRound()
                    },
                    onClose: { [weak self] in
                        self?.dismissCompletion()
                    }
                )
                CompletionNotifier.shared.notify(
                    taskCount: finished.taskIDs.count,
                    durationSeconds: finished.durationMs / 1000
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
        UserDefaults.standard.object(forKey: "jingli.autoDND") as? Bool ?? true
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
        return 5 * 60 * 1000
    }

    func openTaskEditor(projectID: String? = nil, lane: String? = nil) {
        taskEditorProjectID = projectID
        taskEditorLane = lane
        isTaskEditorPresented = true
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

    func goBack() {
        switch page {
        case .project:
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
        projectTasks(id).count
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
            "taskIds": timer?.taskIDs ?? []
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

    func agentNextRound() throws -> [String: Any] {
        guard completion != nil else {
            throw AgentError.invalidParams("本轮尚未结束")
        }
        startNextRound()
        guard timerIsActive else {
            throw AgentError.invalidParams("没有可复用的未完成任务")
        }
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
