import SwiftUI
import JingliCore

/// 一轮结束后：逐个任务显示 +1/n，先休息再开下一轮。
struct CompletionSheet: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let completion: FocusCompletion

    private var titles: [(id: String, title: String, share: Double)] {
        let all = model.snapshot?.todayTasks ?? []
        return completion.taskIDs.map { id in
            (id, all.first { $0.id == id }?.title ?? "任务", completion.shares[id] ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本轮完成").font(.system(size: 21, weight: .bold)).foregroundStyle(Tokens.text)
                    Text("\(completion.taskIDs.count) 件任务共享 25 分钟")
                        .font(.system(size: 11.5)).foregroundStyle(Tokens.text3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.stats?.pomodoros ?? 0)")
                        .font(.system(size: 26, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.88, green: 0.54, blue: 0.39))
                    Text("今日番茄").font(.system(size: 10)).foregroundStyle(Tokens.text3)
                }
            }
            .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(titles, id: \.id) { item in
                    HStack {
                        Text(item.title).font(.system(size: 13.5)).foregroundStyle(Tokens.text)
                        Spacer()
                        Text("+1/\(completion.taskIDs.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.88, green: 0.54, blue: 0.39))
                    }
                    .padding(.vertical, 12)
                    if item.id != titles.last?.id { Divider().overlay(Tokens.line) }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
            .padding(.top, 18)

            HStack(spacing: 6) {
                Circle().fill(Tokens.green).frame(width: 5, height: 5)
                Text(model.longBreakPending
                     ? "连续 4 个钟了，这次休息 25 分钟"
                     : "连续 \(model.stats?.pomodoros ?? 0) 个钟，再 \(4 - (model.stats?.pomodoros ?? 0) % 4) 个就是长休")
                    .font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
            }
            .padding(.top, 12)

            Button {
                model.startBreak()
                dismiss()
            } label: {
                Text("开始休息 \(model.longBreakPending ? 25 : 5) 分钟")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.03, green: 0.07, blue: 0.05))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Tokens.green, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            Button {
                model.dismissCompletion()
                dismiss()
            } label: {
                Text("回到清单")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.text2)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Tokens.line))
            }
            .buttonStyle(.plain)
            .padding(.top, 9)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Tokens.bg)
    }

}


/// 休息倒计时条：显示在「今天」顶部，可以跳过。
struct BreakBanner: View {
    @Environment(IOSAppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("休息中 · \(model.breakMinutes) 分钟")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Tokens.text)
                    Text("还剩 \(remainingText)")
                        .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(Tokens.text3)
                }
                Spacer()
                Button {
                    model.skipBreak()
                } label: {
                    Text("跳过")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tokens.text2)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Tokens.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Tokens.green.opacity(0.26)))
        }
    }

    private var remainingText: String {
        let ms = model.breakRemainingMs
        let seconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
