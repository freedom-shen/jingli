import SwiftUI
import JingliCore

struct RootView: View {
    @State private var focusMessage = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("开启一天")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Text("主线已选 0 / 4")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)

                    Button("勿扰开") {
                        do {
                            try FocusController.shared.enable()
                            focusMessage = "勿扰已开启"
                        } catch {
                            focusMessage = "勿扰失败：\(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("focus-on")

                    Button("勿扰关") {
                        do {
                            try FocusController.shared.disable()
                            focusMessage = "勿扰已关闭"
                        } catch {
                            focusMessage = "勿扰失败：\(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("focus-off")

                    Button("显示浮窗") {
                        FloatingPanelController.shared.show()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("show-floating-panel")

                    Button("隐藏浮窗") {
                        FloatingPanelController.shared.hide()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("hide-floating-panel")
                }

                Text("Phase 0 骨架已就绪。下一步接入任务、计时与截图模式。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)

                if !focusMessage.isEmpty {
                    Text(focusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }

                Spacer()
            }
            .padding(40)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .preferredColorScheme(.dark)
    }
}
