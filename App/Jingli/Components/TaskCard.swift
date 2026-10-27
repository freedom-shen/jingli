import SwiftUI
import JingliCore

struct TaskCard: View {
    let task: Task
    var selected: Bool?
    var disabled = false
    var focusState: TaskFocusState = .none
    var addsToRound = false
    var pomodoroCount: Double = 0
    /// 有项目时徽章显示项目名；nil 时回退成「主线 / 临时」。
    var projectName: String?
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

            if !task.note.isEmpty {
                Text(task.note.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(badgeText)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .foregroundStyle(Theme.textSecondary)
                    .help(badgeHelp)

                if let estimate = task.estimate {
                    pomodoroEstimate(estimate: estimate)
                } else if pomodoroCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Theme.tomato.opacity(0.85))
                            .frame(width: 5, height: 5)

                        Text(formatPomodoros(pomodoroCount))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    .help("今日已用 \(formatPomodoros(pomodoroCount)) 个番茄")
                    .accessibilityLabel("今日已用 \(formatPomodoros(pomodoroCount)) 个番茄")
                }

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

                        if let onDetail {
                            Button(action: { onDetail() }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(TaskIconButtonStyle())
                            .help("编辑详情")
                            .accessibilityLabel("编辑详情")
                        }
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

    private var badgeText: String {
        if task.lane == "temporary" { return "临时" }
        if let projectName, !projectName.isEmpty { return projectName }
        return "主线"
    }

    private var badgeHelp: String {
        if task.lane == "temporary" { return "临时任务" }
        if let projectName, !projectName.isEmpty { return "主线任务 · \(projectName)" }
        return "主线任务"
    }

    private func formatPomodoros(_ value: Double) -> String {
        let rounded = FocusCredit.roundedForDisplay(value)
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%g", rounded)
    }

    /// 今天已用 / 预计：进度环 + 数字；超出预计时整体变番茄色。
    private func pomodoroEstimate(estimate: Int) -> some View {
        let used = pomodoroCount
        let over = used > Double(estimate)
        let progress = estimate > 0 ? min(1, used / Double(estimate)) : 0

        return HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.13), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        over ? Theme.tomato : Theme.tomato.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 13, height: 13)

            Text("\(formatPomodoros(used)) / \(estimate)\(over ? " 超出" : "")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(over ? Theme.tomato : Theme.textSecondary)
                .monospacedDigit()
        }
        .help("今日已用 \(formatPomodoros(used)) 个番茄，预计 \(estimate) 个")
        .accessibilityLabel("今日已用 \(formatPomodoros(used)) 个番茄，预计 \(estimate) 个")
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
