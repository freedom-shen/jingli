import SwiftUI
import JingliCore

struct TaskCard: View {
    let task: Task
    var selected: Bool?
    var disabled = false
    var focusState: TaskFocusState = .none
    var addsToRound = false
    var onToggleSelection: (() -> Void)?
    var onDone: (() -> Void)?
    var onPlay: (() -> Void)?
    var onDetail: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(task.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(task.done, color: Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if let selected {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(selected ? Theme.accent : Theme.textSecondary.opacity(0.45))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(task.lane == "temporary" ? "临时" : "主线")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .foregroundStyle(Theme.textSecondary)

                Spacer(minLength: 0)

                if selected == nil {
                    HStack(spacing: 6) {
                        Button(action: { onPlay?() }) {
                            Image(systemName: playIcon)
                                .font(.system(size: addsToRound ? 12 : 10, weight: addsToRound ? .semibold : .regular))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(TaskIconButtonStyle(active: focusState != .none))
                        .help(playHelp)
                        .accessibilityLabel(playHelp)

                        Button(action: { onDone?() }) {
                            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(TaskIconButtonStyle(active: task.done))
                        .help(task.done ? "恢复任务" : "完成任务")

                        Button(action: { onDetail?() }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(TaskIconButtonStyle())
                        .help("任务详情")
                        .accessibilityLabel("任务详情")
                    }
                }
            }
        }
        .padding(14)
        .frame(height: 112)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    selected == true ? Theme.accent : Color.white.opacity(0.06),
                    lineWidth: selected == true ? 1.5 : 1
                )
        )
        .opacity(disabled ? 0.4 : (task.done ? 0.45 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard !disabled else { return }
            onToggleSelection?()
        }
    }

    private var playIcon: String {
        if addsToRound { return "plus" }
        return focusState == .running ? "pause.fill" : "play.fill"
    }

    private var playHelp: String {
        if addsToRound { return "加入本轮" }
        return focusState == .running ? "暂停专注" : "开始专注"
    }
}

private struct TaskIconButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? Theme.accent.opacity(0.16) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
