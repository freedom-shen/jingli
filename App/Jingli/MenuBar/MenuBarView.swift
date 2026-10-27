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
                Text(model.isStandby ? "待机" : model.displayText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        (model.isOnBreak || model.isStandby)
                            ? Theme.breakGreen
                            : Theme.textPrimary
                    )
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

            Button("快速添加任务") {
                NSApp.keyWindow?.orderOut(nil)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows
                    .first(where: { !($0 is FloatingPanel) })?
                    .makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    model.openAddTask()
                }
            }

            Button("打开精力管理") {
                NSApp.keyWindow?.orderOut(nil)
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
        if model.isStandby { return "今日 \(model.todayPomodoroCount) 个番茄 · 已完成" }
        guard model.timerIsActive else { return "未开始" }
        return model.timerIsPaused ? "已暂停" : "专注中"
    }

    private var participantsText: String {
        if model.isOnBreak { return "休息 \(model.breakMinutes) 分钟" }
        if model.isStandby {
            let count = model.lastRoundTasks.count
            return count > 0 ? "上一轮 \(count) 件任务" : "从今日页开始一件任务"
        }
        guard let timer = model.timer, model.timerIsActive else {
            return "从今日页开始一件任务"
        }
        return "本轮 \(timer.taskIDs.count) 件任务"
    }
}
