import AppKit
import SwiftUI

/// 菜单栏图标的状态，决定图标和颜色。
enum MenuBarState: Equatable {
    case idle
    case focusing
    case paused
    case onBreak
}

/// 菜单栏那一小块长什么样。
///
/// MenuBarExtra 的 label 会被系统当模板渲染：`Text` 上设颜色、`foregroundStyle` 都不起作用。
/// 唯一能透出颜色的办法是把符号和文字画进一张图片，再用 `.renderingMode(.original)` 显示。
struct MenuBarLook: Equatable {
    let symbolName: String
    let colorName: String
    let color: NSColor

    static let breakGreen = NSColor(srgbRed: 0.48, green: 0.74, blue: 0.56, alpha: 1)

    static func make(for state: MenuBarState) -> MenuBarLook {
        switch state {
        case .onBreak:
            return MenuBarLook(symbolName: "cup.and.saucer", colorName: "break-green", color: breakGreen)
        case .paused:
            return MenuBarLook(symbolName: "timer", colorName: "secondary", color: .secondaryLabelColor)
        case .focusing, .idle:
            // labelColor：深色菜单栏里就是白色，浅色菜单栏里自动转黑
            return MenuBarLook(symbolName: "timer", colorName: "label", color: .labelColor)
        }
    }
}

extension AppModel {
    var menuBarState: MenuBarState {
        if isOnBreak { return .onBreak }
        if isBusy { return timerIsPaused ? .paused : .focusing }
        return .idle
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let text = model.isBusy ? model.displayText : "精力"
        Image(nsImage: MenuBarLabelImage.make(text: text, state: model.menuBarState))
            .renderingMode(.original)
            .accessibilityLabel("精力管理 · \(text)")
    }
}

/// 把「符号 + 时间」画成一张带颜色的图片，宽度按文字实测，跟系统图标并排不挤。
enum MenuBarLabelImage {
    static func make(text: String, state: MenuBarState) -> NSImage {
        let look = MenuBarLook.make(for: state)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: look.color,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)

        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        let symbol = NSImage(systemSymbolName: look.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .tinted(look.color)
        let symbolSize = symbol?.size ?? .zero
        let spacing: CGFloat = symbolSize.width > 0 ? 4 : 0
        let height = max(textSize.height, symbolSize.height)
        let size = NSSize(width: symbolSize.width + spacing + textSize.width + 2, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            symbol?.draw(
                in: NSRect(x: 1, y: (height - symbolSize.height) / 2, width: symbolSize.width, height: symbolSize.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            (text as NSString).draw(
                at: NSPoint(x: 1 + symbolSize.width + spacing, y: (height - textSize.height) / 2),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = false
        return image
    }
}

private extension NSImage {
    /// 模板符号按指定颜色重画一份。
    func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            rect.fill()
            self.draw(in: rect, from: .zero, operation: .sourceIn, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel
    /// 弹窗自己收起来；菜单栏那一层负责，View 不直接碰 NSWindow
    var dismiss: () -> Void = {}

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
                dismiss()
                model.openMainWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    model.openAddTask()
                }
            }

            Button("打开精力管理") {
                dismiss()
                model.openMainWindow()
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
