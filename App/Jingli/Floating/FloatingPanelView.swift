import SwiftUI
import JingliCore

struct FloatingPanelView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("浮动番茄钟")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

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

            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.tomato)
                    .frame(width: 140, height: 140)
                    .shadow(color: Theme.tomato.opacity(0.35), radius: 24, y: 10)

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

            Text(participantsText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

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
            } else {
                Text("从今日页开始一件任务")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .padding(16)
        .frame(width: 260, height: 360)
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

    private var statusText: String {
        if model.isOnBreak { return "休息中" }
        guard model.timerIsActive else { return "25 分钟专注" }
        return model.timerIsPaused ? "已暂停" : "专注中"
    }

    private var participantsText: String {
        if model.isOnBreak { return "休息 5 分钟" }
        guard let timer = model.timer, model.timerIsActive else {
            return "本轮 0 件任务"
        }
        return "本轮 \(timer.taskIDs.count) 件任务"
    }
}
