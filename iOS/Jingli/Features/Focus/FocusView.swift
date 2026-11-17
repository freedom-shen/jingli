import SwiftUI
import JingliCore

/// 一轮番茄：整屏只留倒计时和本轮任务。
struct FocusView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var now = Date()

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Tokens.bg.ignoresSafeArea()
            RadialGradient(
                colors: [Tokens.tomato.opacity(0.18), .clear],
                center: .top, startRadius: 20, endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Tokens.tomato).frame(width: 6, height: 6)
                    Text("专注中 · 第 \(roundNumber) 轮")
                        .font(.system(size: 10.5)).tracking(1.2)
                        .foregroundStyle(Tokens.text3)
                }
                .padding(.top, 28)

                ring
                    .padding(.top, 22)

                Text(taskTitles.count > 1
                     ? "本轮 \(taskTitles.count) 件任务共同计时"
                     : "本轮专注这一件事")
                    .font(.system(size: 13)).foregroundStyle(Tokens.text2)
                    .padding(.top, 24)
                if taskTitles.count > 1 {
                    Text("结束后按 1/\(taskTitles.count) 分摊")
                        .font(.system(size: 11)).foregroundStyle(Tokens.text3)
                        .padding(.top, 4)
                }

                VStack(spacing: 8) {
                    ForEach(taskTitles, id: \.self) { title in
                        HStack {
                            Text(title).font(.system(size: 13)).foregroundStyle(Tokens.text)
                            Spacer()
                            Text(taskTitles.count > 1 ? "1/\(taskTitles.count)" : "全部")
                                .font(.system(size: 11)).foregroundStyle(Tokens.text3)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.06)))
                    }
                }
                .padding(.top, 28)

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        model.finishRound()
                    } label: {
                        Text("结束本轮")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.text2)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Tokens.line))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if model.timer?.phase == .paused { model.resumeFocus() } else { model.pauseFocus() }
                    } label: {
                        Text(model.timer?.phase == .paused ? "继续" : "暂停")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Tokens.accent, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 18)

                Text("锁屏后仍按结束时间计时")
                    .font(.system(size: 10)).foregroundStyle(Tokens.text3)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 24)
        }
        .onReceive(ticker) { value in
            now = value
            model.tick()
        }
    }

    private var ring: some View {
        let total = Double(model.timer?.durationMs ?? FocusTimer.defaultDurationMs)
        let remaining = Double(model.timer?.remaining(now: nowMs) ?? 0)
        let progress = total > 0 ? max(0, min(1, remaining / total)) : 0
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [Color(red: 0.88, green: 0.54, blue: 0.39), Tokens.tomato],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(formatted(model.timer?.remaining(now: nowMs) ?? 0))
                    .font(.system(size: 52, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.text)
                Text("剩余 · 共 \(Int(total / 60000)):00")
                    .font(.system(size: 11)).foregroundStyle(Tokens.text3)
            }
        }
        .frame(width: 270, height: 270)
    }

    private var nowMs: Int64 { Int64(now.timeIntervalSince1970 * 1000) }

    private var roundNumber: Int {
        (model.stats?.pomodoros ?? 0) + 1
    }

    private var taskTitles: [String] {
        guard let ids = model.timer?.taskIDs else { return [] }
        let all = model.snapshot?.todayTasks ?? []
        return ids.map { id in all.first { $0.id == id }?.title ?? "任务" }
    }

    private func formatted(_ ms: Int) -> String {
        let seconds = max(0, Int(ceil(Double(ms) / 1000)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
