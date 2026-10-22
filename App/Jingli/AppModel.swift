import Foundation
import JingliCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: TodaySnapshot?
    @Published var selected: Set<String> = []
    @Published var errorMessage: String?
    @Published var isTaskEditorPresented = false

    private let store: WorkspaceStore

    init(store: WorkspaceStore = AppServices.shared.store) {
        self.store = store
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
        do {
            try store.resetDay()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleDone(_ task: Task) {
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

    func openTaskEditor() {
        isTaskEditorPresented = true
    }
}
