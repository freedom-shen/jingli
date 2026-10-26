import SwiftUI
import JingliCore

struct TaskDetailView: View {
    @ObservedObject var model: AppModel
    let task: Task
    let locked: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var note: String
    @State private var estimate: Int?
    @State private var confirmDelete = false

    init(model: AppModel, task: Task, locked: Bool = false) {
        self.model = model
        self.task = task
        self.locked = locked
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note)
        _estimate = State(initialValue: task.estimate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            titleField
            metaRow
            detailSection
            footer
        }
        .padding(24)
        .frame(width: 780)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("任务详情")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(task.lane == "temporary" ? "临时任务" : "主线任务")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("close-task-detail")
        }
    }

    private var titleField: some View {
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
    }

    private var metaRow: some View {
        HStack(alignment: .top, spacing: 24) {
            metaItem("所属项目", value: model.projectName(for: task))

            VStack(alignment: .leading, spacing: 6) {
                Text("预计番茄")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    estimateStepper
                    Text(estimateHint)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.75))
                }
            }

            metaItem("今日已用", value: usedText)
            metaItem("创建于", value: String(task.createdAt.prefix(10)))
        }
    }

    private func metaItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(minWidth: 90, alignment: .leading)
    }

    private var estimateStepper: some View {
        HStack(spacing: 0) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(locked)

            Text(estimate.map(String.init) ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 26)
                .foregroundStyle(estimate == nil ? Theme.textSecondary : Theme.textPrimary)

            Button {
                step(1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(locked)
        }
        .foregroundStyle(Theme.textSecondary)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(height: 26)
        .accessibilityIdentifier("task-detail-estimate")
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("详情")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if locked {
                    Text("主线任务在项目中维护")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
            }

            MarkdownEditorView(text: $note, editable: !locked)
                .accessibilityIdentifier("task-detail-note")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
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
                    if model.updateTask(
                        id: task.id,
                        title: title,
                        note: note,
                        estimate: estimate
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(CompactPrimaryButtonStyle())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("save-task-detail")
            }
        }
    }

    private var estimateHint: String {
        guard let estimate else { return "未估" }
        return "≈ \(estimate * 25) 分钟"
    }

    private var usedText: String {
        let used = model.creditedPomodoros(for: task)
        let formatted = FocusCredit.roundedForDisplay(used)
        let text = formatted == formatted.rounded()
            ? String(format: "%.0f", formatted)
            : String(format: "%g", formatted)
        if let estimate {
            return "\(text) / \(estimate)"
        }
        return text
    }

    private func step(_ delta: Int) {
        guard !locked else { return }
        guard let current = estimate else {
            if delta > 0 { estimate = 1 }
            return
        }
        let next = current + delta
        if next < 1 {
            estimate = nil
        } else {
            estimate = min(32, next)
        }
    }
}
