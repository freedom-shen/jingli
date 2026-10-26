import SwiftUI
import JingliCore

struct TemporaryTasksView: View {
    @ObservedObject var model: AppModel
    @State private var deleteTarget: Task?

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 180), spacing: 12),
        count: 4
    )

    var body: some View {
        let tasks = model.temporaryTasks

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("任务 \(tasks.count)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Button("添加任务") {
                        model.openTaskEditor(lane: "temporary")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("new-temporary-task-button")
                }

                if tasks.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tasks) { task in
                            card(task)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
        .alert(
            "删除临时任务？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let task = deleteTarget {
                    model.deleteTask(task)
                }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text(deleteTarget?.title ?? "")
        }
    }

    private func card(_ task: Task) -> some View {
        TaskCard(
            task: task,
            focusState: model.focusState(for: task),
            addsToRound: model.canAddToRound(task),
            pomodoroCount: model.creditedPomodoros(for: task),
            onDone: { model.toggleDone(task) },
            onPlay: { model.toggleFocus(for: task) },
            onDetail: { model.openTaskDetail(task) }
        )
        .contextMenu {
            Button("任务详情") {
                model.openTaskDetail(task)
            }

            if !model.isInToday(task) {
                Button("加入今天") {
                    model.addExistingToToday(task)
                }
            }

            Divider()

            Button("删除任务", role: .destructive) {
                deleteTarget = task
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("还没有临时任务")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Text("随手记下来的事放这里，不占主线名额。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

            Button("记一件临时任务") {
                model.openTaskEditor(lane: "temporary")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
    }
}
