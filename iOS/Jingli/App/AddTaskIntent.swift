import AppIntents
import Foundation
import JingliCore

/// 快捷指令 / Siri：一句话把任务加进今天。
/// 只写本地库，回到 App 后由同步节拍推上去。
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "加一个任务" }
    static var description: IntentDescription {
        IntentDescription("把一条任务加到「精力管理」的今天，类型和预估可选。")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "任务内容")
    var title: String

    @Parameter(title: "类型", default: .temporary)
    var lane: TaskLane

    @Parameter(title: "预估番茄数", description: "1–32，留空表示不估")
    var estimate: Int?

    init() {}

    init(title: String, lane: TaskLane = .temporary, estimate: Int? = nil) {
        self.title = title
        self.lane = lane
        self.estimate = estimate
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "任务内容是空的，没加。")
        }

        AppPaths.containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.freedom-shen.jingli")
        let database = try JingliDatabase.onDisk(at: AppPaths.databaseURL)
        let store = WorkspaceStore(database: database)
        let clamped = estimate.map { min(max($0, 1), 32) }
        let task = try store.createTask(
            title: trimmed,
            lane: lane.rawValue,
            plannedDate: DayKey.make(),
            estimate: clamped
        )

        let laneText = task.lane == "main" ? "主线" : "临时"
        return .result(dialog: "已加入今天：\(task.title)（\(laneText)）")
    }
}

enum TaskLane: String, AppEnum {
    case main
    case temporary

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "任务类型") }
    static var caseDisplayRepresentations: [TaskLane: DisplayRepresentation] {
        [
            .main: "主线（占 1 个名额）",
            .temporary: "临时（不占名额）",
        ]
    }
}

struct JingliShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "用\(.applicationName)加个任务",
                "在\(.applicationName)记一笔",
            ],
            shortTitle: "加任务",
            systemImageName: "plus.circle"
        )
    }
}
