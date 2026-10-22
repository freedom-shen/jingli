import SwiftUI

struct FloatingPanelView: View {
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

                Text("25:00")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            Text("本轮 0 件任务")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Text("P0-2 NSPanel spike")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
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
}
