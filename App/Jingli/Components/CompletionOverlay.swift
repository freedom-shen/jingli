import SwiftUI
import JingliCore

struct CompletionOverlay: View {
    let completion: FocusCompletion
    let tasks: [Task]
    var dimmed = true
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if dimmed {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
            }

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("本轮番茄钟完成")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("25 分钟 · \(completion.taskIDs.count) 件任务共同计时")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 8) {
                    ForEach(completion.taskIDs, id: \.self) { taskID in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.tomato)
                                .frame(width: 6, height: 6)
                            Text(title(for: taskID))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("+\(format(completion.shares[taskID] ?? 0))")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }

                Button("关闭") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.textPrimary)
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("completion-close-button")
            }
            .padding(22)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 18)
        }
    }

    private func title(for taskID: String) -> String {
        tasks.first { $0.id == taskID }?.title ?? "任务"
    }

    private func format(_ value: Double) -> String {
        let rounded = FocusCredit.roundedForDisplay(value)
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
    }
}
