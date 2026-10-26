import SwiftUI
import JingliCore

struct FloatingPanelView: View {
    @ObservedObject var model: AppModel
    let mode: FloatingPanelMode
    let onShrink: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        if mode == .mini {
            miniPanel
        } else {
            standardPanel
        }
    }

    private var miniPanel: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: model.isOnBreak
                            ? [Theme.breakGreenLight, Theme.breakGreenDark]
                            : [
                                Color(red: 0.84, green: 0.42, blue: 0.29),
                                Color(red: 0.62, green: 0.24, blue: 0.16)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .trim(from: 0, to: model.panelProgress)
                .stroke(arcColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(7)

            VStack(spacing: 3) {
                Text(model.displayText)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(model.timerIsPaused ? 0.72 : 1))
                    .monospacedDigit()

                Circle()
                    .fill(dotColor)
                    .frame(width: 4, height: 4)
            }
        }
        .opacity(model.timerIsPaused ? 0.88 : 1)
        .frame(width: 96, height: 96)
        .contentShape(Circle())
        .onTapGesture { onExpand() }
        .help("点击放大")
        .accessibilityLabel("浮窗倒计时，点击放大")
        .accessibilityIdentifier("floating-panel-mini")
    }

    private var standardPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("浮动番茄钟")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onShrink) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("缩小为倒计时")
                    .accessibilityLabel("缩小浮窗")
                    .accessibilityIdentifier("floating-panel-shrink")

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("floating-panel-close")
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(model.isOnBreak ? Theme.breakGreen : Theme.tomato)
                    .frame(width: 140, height: 140)
                    .shadow(
                        color: (model.isOnBreak ? Theme.breakGreen : Theme.tomato).opacity(0.35),
                        radius: 24,
                        y: 10
                    )

                VStack(spacing: 2) {
                    Text(model.displayText)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()

                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            roundTasks

            Spacer()

            if model.isBusy {
                HStack(spacing: 8) {
                    if model.isOnBreak {
                        Button("跳过休息") {
                            model.skipBreak()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(model.timerIsPaused ? "继续" : "暂停") {
                            if model.timerIsPaused {
                                model.resumeFocus()
                            } else {
                                model.pauseFocus()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("废弃") {
                            model.abandonFocus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else if !model.lastRoundTasks.isEmpty {
                Button {
                    model.continueLastRound()
                } label: {
                    Text("继续上一轮")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.textPrimary)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("continue-last-round-button")
            } else {
                Text("从今日页开始一件任务")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .padding(16)
        .frame(width: 260, height: 404)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityIdentifier("floating-panel")
    }

    private var arcColor: Color {
        if model.isOnBreak { return Color.white.opacity(0.85) }
        guard model.timerIsActive else { return Color.white.opacity(0.25) }
        return model.timerIsPaused ? Color.white.opacity(0.45) : Color.white.opacity(0.92)
    }

    private var dotColor: Color {
        if model.isOnBreak { return Color.white.opacity(0.85) }
        guard model.timerIsActive else { return Color.white.opacity(0.30) }
        return model.timerIsPaused ? Color.white.opacity(0.50) : Color.white.opacity(0.95)
    }

    private var statusText: String {
        if model.isOnBreak { return "休息中" }
        guard model.timerIsActive else { return "25 分钟专注" }
        return model.timerIsPaused ? "已暂停" : "专注中"
    }

    @ViewBuilder
    private var roundTasks: some View {
        if model.isOnBreak {
            Text("休息 \(model.breakMinutes) 分钟")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        } else if !model.timerIsActive, !model.lastRoundTasks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("上一轮任务")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(model.lastRoundTasks.count) 件")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }

                ForEach(Array(model.lastRoundTasks.prefix(3))) { task in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Theme.tomato.opacity(0.5))
                            .frame(width: 5, height: 5)

                        Text(task.title)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        Button {
                            model.removeFromLastRound(task.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .help("从这一轮移除")
                        .accessibilityLabel("从上一轮移除 \(task.title)")
                        .accessibilityIdentifier("remove-last-round-\(task.id)")
                    }
                }

                if model.lastRoundTasks.count > 3 {
                    Text("还有 \(model.lastRoundTasks.count - 3) 件")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if roundTaskRows.isEmpty {
            Text("本轮 0 件任务")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("本轮任务")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(roundTaskRows.count) 件")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }

                ForEach(Array(roundTaskRows.prefix(3)), id: \.id) { row in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Theme.tomato)
                            .frame(width: 5, height: 5)

                        Text(row.title)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        Text(shareText(total: roundTaskRows.count))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }

                if roundTaskRows.count > 3 {
                    Text("还有 \(roundTaskRows.count - 3) 件")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var roundTaskRows: [(id: String, title: String)] {
        guard let timer = model.timer, timer.isActive else { return [] }
        let titles = Dictionary(
            (model.snapshot?.todayTasks ?? []).map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        return timer.taskIDs.map { id in
            (id: id, title: titles[id] ?? "任务已删除")
        }
    }

    private func shareText(total: Int) -> String {
        total > 1 ? "1/\(total)" : "1"
    }
}
