import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
            Text(model.isBusy ? model.displayText : "精力")
                .monospacedDigit()
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.displayText)
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
        if model.isOnBreak { return "休息中" }
        guard model.timerIsActive else { return "未开始" }
        return model.timerIsPaused ? "已暂停" : "专注中"
    }

    private var participantsText: String {
        if model.isOnBreak { return "休息 5 分钟" }
        guard let timer = model.timer, model.timerIsActive else {
            return "从今日页开始一件任务"
        }
        return "本轮 \(timer.taskIDs.count) 件任务"
    }
}
