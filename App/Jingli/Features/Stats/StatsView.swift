import SwiftUI
import JingliCore

struct StatsView: View {
    @ObservedObject var model: AppModel

    private var stats: TodayStats {
        model.stats ?? TodayStats(pomodoros: 0, focusSeconds: 0, completedTasks: 0, records: [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    kpiCard(
                        value: "\(stats.pomodoros)",
                        unit: "个",
                        title: "今日番茄钟",
                        accent: Theme.tomato
                    )
                    kpiCard(
                        value: focusDurationText,
                        unit: "",
                        title: "今日专注时长",
                        accent: Theme.accent
                    )
                    kpiCard(
                        value: "\(stats.completedTasks)",
                        unit: "件",
                        title: "今日完成任务",
                        accent: Theme.projectColor("sage")
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("今日专注记录")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if stats.records.isEmpty {
                        Text("今天还没有完成的番茄钟。开始一件任务，专注 25 分钟。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.card)
                            )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(stats.records) { record in
                                recordRow(record)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
        .accessibilityIdentifier("stats-page")
    }

    private func kpiCard(value: String, unit: String, title: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func recordRow(_ record: FocusRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recordTime(record.startedAt))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text("\(record.durationSec / 60) 分钟")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(record.tasks) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.tomato)
                            .frame(width: 5, height: 5)
                        Text(task.title)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("+\(format(task.share))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var focusDurationText: String {
        if stats.focusSeconds > 0, stats.focusSeconds < 60 {
            return "\(stats.focusSeconds) 秒"
        }
        let minutes = stats.focusSeconds / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours) 小时" : "\(hours) 时 \(rest) 分"
        }
        return "\(minutes) 分钟"
    }

    private func format(_ value: Double) -> String {
        let rounded = FocusCredit.roundedForDisplay(value)
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
    }

    private func recordTime(_ timestamp: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: timestamp) else {
            return "--:--"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
