import SwiftUI
import JingliCore

/// 统计：只看今天。历史回顾交给助手 / 详细统计，不在这里堆图表。
struct StatsView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var showAssistant = false
    @State private var prefill: String?

    private var stats: TodayStats? { model.stats }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                kpis.padding(.top, 18)
                recordsHeader.padding(.top, 26)
                recordList
                hint.padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.today).font(.footnote).foregroundStyle(Tokens.text3)
                Text("统计").font(.system(size: 30, weight: .bold)).foregroundStyle(Tokens.text)
            }
            Spacer()
            Button {
                prefill = "上周专注了多少？"
                showAssistant = true
            } label: {
                HStack(spacing: 4) {
                    Text("历史回顾")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.text2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Tokens.text3)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(Tokens.line))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stats.history")
        }
        .padding(.top, 8)
    }

    private var kpis: some View {
        HStack(spacing: 9) {
            kpi(value: "\(stats?.pomodoros ?? 0)", label: "番茄")
            kpi(value: "\(Int((stats?.focusSeconds ?? 0) / 60))", label: "分钟专注")
            kpi(value: "\(stats?.completedTasks ?? 0)", label: "完成任务")
        }
    }

    private func kpi(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tokens.text)
            Text(label).font(.system(size: 10)).foregroundStyle(Tokens.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
    }

    private var recordsHeader: some View {
        HStack {
            Text("今日记录").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tokens.text)
            Spacer()
            Text("\(stats?.records.count ?? 0) 轮")
                .font(.system(size: 11)).foregroundStyle(Tokens.text3)
        }
        .padding(.bottom, 10)
    }

    private var recordList: some View {
        VStack(spacing: 0) {
            let records = stats?.records ?? []
            if records.isEmpty {
                Text("今天还没有完成的番茄")
                    .font(.system(size: 12)).foregroundStyle(Tokens.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    recordRow(record)
                    if index < records.count - 1 {
                        Divider().overlay(Tokens.line)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
    }

    private func recordRow(_ record: FocusRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeRange(record))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Tokens.text3)
                .frame(width: 82, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.tasks.map(\.title).joined(separator: " · "))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Tokens.text)
                    .lineLimit(2)
                Text(subtitle(record))
                    .font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
            }

            Spacer(minLength: 8)

            Text("+1")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.tomato)
        }
        .padding(.vertical, 12)
    }

    private var hint: some View {
        Button {
            prefill = "上周专注了多少？"
            showAssistant = true
        } label: {
            HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("想看上周？直接问助手").font(.system(size: 12.5)).foregroundStyle(Tokens.text)
                Text("「上周专注了多少」").font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.text3)
        }
            .padding(14)
            .background(Tokens.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.accent.opacity(0.20)))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showAssistant) {
            AssistantView(prefill: prefill)
        }
    }

    // MARK: - 格式化

    private static let iso = ISO8601DateFormatter()
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func timeRange(_ record: FocusRecord) -> String {
        guard let start = Self.iso.date(from: record.startedAt) else { return "--:--" }
        let end = start.addingTimeInterval(TimeInterval(record.durationSec))
        return "\(Self.clock.string(from: start))–\(Self.clock.string(from: end))"
    }

    private func subtitle(_ record: FocusRecord) -> String {
        if record.tasks.count > 1 {
            return "共享 \(record.tasks.count) 件 · 各 +1/\(record.tasks.count)"
        }
        return "1 个番茄 · \(record.durationSec / 60) 分钟"
    }
}
