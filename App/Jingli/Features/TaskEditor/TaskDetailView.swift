import SwiftUI
import JingliCore

struct TaskDetailView: View {
    @ObservedObject var model: AppModel
    let task: Task
    let locked: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var note: String
    @State private var confirmDelete = false

    init(model: AppModel, task: Task, locked: Bool = false) {
        self.model = model
        self.task = task
        self.locked = locked
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("任务详情")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text(task.lane == "temporary" ? "临时任务" : "主线任务")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .foregroundStyle(Theme.textSecondary)
            }

            if locked {
                Text("主线任务在项目中维护，这里只能查看和完成任务。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("任务名称")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("任务名称", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.card)
                    )
                    .disabled(locked)
                    .accessibilityIdentifier("task-detail-title")
            }

            HStack(alignment: .top, spacing: 24) {
                detailItem("所属项目", model.projectName(for: task))
                detailItem("今日番茄", pomodoroText)
                detailItem("创建于", String(task.createdAt.prefix(10)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                if locked {
                    Text(task.note.isEmpty ? "无备注" : task.note)
                        .font(.system(size: 13))
                        .foregroundStyle(
                            task.note.isEmpty ? Theme.textSecondary : Theme.textPrimary
                        )
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.card)
                        )
                        .accessibilityIdentifier("task-detail-note")
                } else {
                    TextEditor(text: $note)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 110)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.card)
                        )
                        .accessibilityIdentifier("task-detail-note")
                }
            }

            HStack {
                Button(task.done ? "恢复任务" : "完成任务") {
                    model.toggleDetailDone()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("toggle-task-detail-done")

                if task.lane == "temporary", !locked {
                    Button("删除任务", role: .destructive) {
                        confirmDelete = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("delete-temporary-task")
                }

                Spacer()

                if locked {
                    Button("关闭") { dismiss() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("close-task-detail")
                } else {
                    Button("取消") { dismiss() }
                        .buttonStyle(.bordered)

                    Button("保存") {
                        if model.updateTask(id: task.id, title: title, note: note) {
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.textPrimary)
                    .foregroundStyle(Theme.background)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("save-task-detail")
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .alert("删除临时任务？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                model.deleteTask(task)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(task.title)
        }
    }

    private var pomodoroText: String {
        let total = model.creditedPomodoros(for: task)
        return String(format: "%g", total)
    }

    private func detailItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
