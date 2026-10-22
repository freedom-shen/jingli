import SwiftUI
import JingliCore

struct RootView: View {
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

                Spacer()
            }
            .padding(40)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .preferredColorScheme(.dark)
    }
}
