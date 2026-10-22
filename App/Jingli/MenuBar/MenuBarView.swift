import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
            Text(model.timerIsActive ? model.timerText : "精力")
                .monospacedDigit()
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.timerText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()

                Spacer()

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(participantsText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

            if model.timerIsActive {
                HStack(spacing: 8) {
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

            Divider()

            Button("打开精力管理") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows
                    .first(where: { !($0 is FloatingPanel) })?
                    .makeKeyAndOrderFront(nil)
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 240)
        .preferredColorScheme(.dark)
    }

    private var statusText: String {
        guard model.timerIsActive else { return "未开始" }
        return model.timerIsPaused ? "已暂停" : "专注中"
    }

    private var participantsText: String {
        guard let timer = model.timer, model.timerIsActive else {
            return "从今日页开始一件任务"
        }
        return "本轮 \(timer.taskIDs.count) 件任务"
    }
}
