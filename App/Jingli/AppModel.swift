import Foundation
import JingliCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: TodaySnapshot?
    @Published var selected: Set<String> = []
    @Published var errorMessage: String?
    @Published var isTaskEditorPresented = false
    @Published private(set) var timer: FocusTimer?
    @Published private(set) var timerText = "25:00"
    @Published var completion: FocusCompletion?

    private let store: WorkspaceStore
    private let timerStore: FocusTimerStore

    init(store: WorkspaceStore = AppServices.shared.store) {
        self.store = store
        self.timerStore = FocusTimerStore(database: store.database)
        self.timer = try? timerStore.loadActive()
        updateTimerText()
        reload()
    }

    var dayStarted: Bool {
        snapshot?.dayStarted ?? false
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
            let next = try store.snapshot()
            snapshot = next
            if next.dayStarted {
                selected = []
            } else {
                selected = Set(next.selection)
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

    @discardableResult
    func createTask(title: String, lane: String, projectID: String?) -> Bool {
        do {
            try store.createTask(
                title: title,
                projectID: projectID,
                lane: lane,
                plannedDate: dayStarted ? DayKey.make() : nil
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
            sessionDate: DayKey.make()
        ) else { return }
        next.start(now: nowMilliseconds(), sessionID: UUID().uuidString)
        next.setFocusMode(on: true, owned: true)
        timer = next
        persistTimer()
        updateTimerText()
        try? FocusController.shared.enable()
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
        try? FocusController.shared.disable()
        updateTimerText()
    }

    func tickFocus() {
        guard var current = timer else { return }
        current.tick(now: nowMilliseconds())
        timer = current
        updateTimerText()
        if current.isFinished {
            finish(current)
        }
    }

    func dismissCompletion() {
        completion = nil
        reload()
    }

    private func finish(_ finished: FocusTimer) {
        do {
            completion = try timerStore.complete(finished)
        } catch {
            errorMessage = error.localizedDescription
        }
        timer = nil
        try? FocusController.shared.disable()
        updateTimerText()
        reload()
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
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    func openTaskEditor() {
        isTaskEditorPresented = true
    }
}

enum TaskFocusState {
    case none
    case running
    case paused
}
