import SwiftUI

struct CommandBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("快速命令")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            TextField("开始 写周报 / 新任务 买咖啡 / 统计", text: $model.commandText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.card)
                )
                .focused($focused)
                .onSubmit { model.executeCommand() }
                .accessibilityIdentifier("command-field")

            if let message = model.commandMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tomato)
            } else {
                Text("开始 <任务名> · 新任务 <标题> · 统计")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("执行") { model.executeCommand() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.textPrimary)
                    .foregroundStyle(Theme.background)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("command-run")
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }
}
