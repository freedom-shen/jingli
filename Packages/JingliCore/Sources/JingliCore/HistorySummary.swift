import Foundation

public struct HistoryDistribution: Identifiable, Sendable {
    public let id: String
    public let title: String
    public var seconds: Double
    public var pomodoros: Double
}

public struct HistorySummary: Sendable {
    public let days: [DayHistory]
    public let tasks: [HistoryDistribution]
    public let projects: [HistoryDistribution]
    public var pomodoros: Int { days.reduce(0) { $0 + $1.pomodoros } }
    public var focusSeconds: Int { days.reduce(0) { $0 + $1.focusSeconds } }
    public var completedTasks: Int { days.reduce(0) { $0 + $1.completedTasks.count } }

    public init(days: [DayHistory], tasks: [Task], projects: [Project]) {
        self.days = days
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var byTask: [String: HistoryDistribution] = [:]
        var byProject: [String: HistoryDistribution] = [:]
        for record in days.flatMap(\.records) {
            var allocated = 0.0
            for item in record.tasks {
                let seconds = Double(record.durationSec) * item.share
                allocated += seconds
                var task = byTask[item.id] ?? HistoryDistribution(id: item.id, title: item.title, seconds: 0, pomodoros: 0)
                task.seconds += seconds
                task.pomodoros += item.share
                byTask[item.id] = task
                let source = taskMap[item.id]
                let id = source?.lane == "temporary" ? "temporary" : source?.projectID ?? "uncategorized"
                let title = id == "temporary" ? "临时任务" : projectMap[id]?.name ?? "未分类"
                var project = byProject[id] ?? HistoryDistribution(id: id, title: title, seconds: 0, pomodoros: 0)
                project.seconds += seconds
                project.pomodoros += item.share
                byProject[id] = project
            }
            let remainder = max(0, Double(record.durationSec) - allocated)
            if remainder > 0.001 {
                let id = "unassigned"
                var entry = byProject[id] ?? HistoryDistribution(id: id, title: "未分配记录", seconds: 0, pomodoros: 0)
                entry.seconds += remainder
                byProject[id] = entry
            }
        }
        let order: (HistoryDistribution, HistoryDistribution) -> Bool = {
            $0.seconds == $1.seconds
                ? ($0.title == $1.title ? $0.id < $1.id : $0.title < $1.title)
                : $0.seconds > $1.seconds
        }
        self.tasks = byTask.values.sorted(by: order)
        self.projects = byProject.values.sorted(by: order)
    }
}
