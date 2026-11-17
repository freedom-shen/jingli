import SwiftUI
import JingliCore

@main
struct JingliApp: App {
    var body: some Scene {
        WindowGroup { BootCheckView() }
    }
}

/// M1/T13 的最小验证：iOS 上能不能打开数据库、跑通业务规则。
/// 真正的今天页在 M2 接进来，这里只证明 Core 在 iOS 可用。
struct BootCheckView: View {
    @State private var lines: [String] = ["检查中…"]

    var body: some View {
        NavigationStack {
            List {
                Section("Core") {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.footnote.monospaced())
                    }
                }
                Section("下一步") {
                    Text("M2：今天页 / 开启一天 / 计时").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("精力管理")
            .task { await check() }
        }
    }

    func check() async {
        do {
            let database = try JingliDatabase.inMemory()
            let store = WorkspaceStore(database: database)
            let project = try store.createProject(name: "容器验证")
            let task = try store.createTask(
                title: "在 iOS 上建的第一条任务",
                projectID: project.id,
                lane: "main",
                plannedDate: "2026-11-17"
            )
            let today = try store.todayTasks(today: "2026-11-17")
            let snapshot = try store.snapshot(today: "2026-11-17")
            lines = [
                "数据库：内存库 OK",
                "项目：\(project.name)",
                "任务：\(task.title)（\(task.lane)）",
                "今日任务：\(today.count) 条 · 项目 \(snapshot.projects.count) 个",
                "Core 在 iOS 跑通 ✓",
            ]
        } catch {
            lines = ["失败：\(error.localizedDescription)"]
        }
    }
}
