import SwiftUI
import JingliCore

struct ProjectDetailView: View {
    @ObservedObject var model: AppModel

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 180), spacing: 12),
        count: 4
    )

    var body: some View {
        Group {
            if let project = model.currentProject() {
                content(project)
            } else {
                Text("项目不存在")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
    }

    private func content(_ project: Project) -> some View {
        let tasks = model.projectTasks(project.id)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !project.description.isEmpty {
                    Text(project.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Text("任务 \(tasks.count)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Button("添加任务") {
                        model.openTaskEditor(projectID: project.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if tasks.isEmpty {
                    VStack(spacing: 10) {
                        Text("这个项目还没有任务")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Button("添加第一个任务") {
                            model.openTaskEditor(projectID: project.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.card)
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tasks) { task in
                            TaskCard(
                                task: task,
                                focusState: model.focusState(for: task),
                                onDone: { model.toggleDone(task) },
                                onPlay: { model.toggleFocus(for: task) }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}
