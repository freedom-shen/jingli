import SwiftUI
import Charts
import JingliCore

struct DetailedStatsView: View {
    @ObservedObject var model: AppModel
    let onBack: () -> Void
    var referenceDay: String? = nil
    @State private var range = "最近 7 天"
    @State private var start = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var end = Date()
    @State private var summary: HistorySummary?
    @State private var error: String?
    @State private var recordsExpanded = false
    private let ranges = ["最近 7 天", "最近 30 天", "全部时间", "自定义"]
    private let colors: [Color] = [Theme.accent, Theme.projectColor("sage"), Theme.projectColor("amber"), Theme.projectColor("violet"), Theme.projectColor("slate")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: onBack) { Label("返回今日统计", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("stats-detail-back")
                Text("详细统计").font(.system(size: 25, weight: .semibold))
                Text("看见时间的去向，让下一次投入更有方向。")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                HStack {
                    Picker("时间范围", selection: $range) {
                        ForEach(ranges, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 440)
                    .accessibilityIdentifier("stats-detail-range")
                    Spacer()
                    if let summary, let first = summary.days.last, let last = summary.days.first {
                        Text("\(first.date) — \(last.date) · \(summary.days.count) 天")
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                }
                if range == "自定义" {
                    HStack {
                        DatePicker("开始", selection: $start, displayedComponents: .date)
                            .accessibilityIdentifier("stats-detail-start")
                        DatePicker("结束", selection: $end, displayedComponents: .date)
                            .accessibilityIdentifier("stats-detail-end")
                        Button("应用", action: load).accessibilityIdentifier("stats-detail-apply")
                    }.frame(maxWidth: 560)
                }
                if let error {
                    Text(error).foregroundStyle(Theme.tomato).accessibilityIdentifier("stats-detail-error")
                } else if let summary {
                    metrics(summary)
                    trend(summary)
                    HStack(alignment: .top, spacing: 18) {
                        taskDistribution(summary).frame(maxWidth: .infinity)
                        projectDistribution(summary).frame(maxWidth: .infinity)
                    }
                    records(summary)
                    Text("仅统计完整完成的番茄钟。多任务按份额分摊，不重复计时。项目按任务当前归属统计；已删除任务的时长归入未分配记录。仅展示现有保留历史，无法恢复已丢失的数据。")
                        .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
            }.padding(.bottom, 28)
        }
        .padding(.horizontal, 40).padding(.top, 4)
        .accessibilityIdentifier("stats-detail-page")
        .onAppear(perform: load)
        .onChange(of: range) { _, _ in if range != "自定义" { load() } }
        .onChange(of: model.stats?.pomodoros) { _, _ in load() }
    }

    private func load() {
        do {
            let today = referenceDay ?? DayKey.make()
            let finish = range == "自定义" ? key(end) : today
            let begin: String?
            if range == "全部时间" {
                begin = nil
            } else if range == "自定义" {
                begin = key(start)
            } else {
                let date = dateFromKey(today)
                begin = key(Calendar.current.date(byAdding: .day, value: range == "最近 30 天" ? -29 : -6, to: date)!)
            }
            summary = try model.historySummary(start: begin, end: finish)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func metrics(_ summary: HistorySummary) -> some View {
        HStack(spacing: 12) {
            metric("完成番茄钟", value: "\(summary.pomodoros)", unit: "个", color: Theme.tomato)
            metric("累计专注", value: hours(Double(summary.focusSeconds)), unit: "小时", color: Theme.accent)
            metric("完成任务", value: "\(summary.completedTasks)", unit: "次", color: colors[1])
            metric("日均专注", value: hours(Double(summary.focusSeconds) / Double(max(1, summary.days.count))), unit: "小时", color: colors[2])
        }
    }

    private func metric(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(color)
                Text(unit).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }.monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private struct Bucket: Identifiable {
        let date: Date
        var seconds: Int
        var pomodoros: Int
        var id: Date { date }
    }

    private func buckets(_ summary: HistorySummary) -> [Bucket] {
        let component: Calendar.Component = summary.days.count > 90 ? .month : summary.days.count > 14 ? .weekOfYear : .day
        var values: [Date: Bucket] = [:]
        for day in summary.days {
            let date = Calendar.current.dateInterval(of: component, for: dateFromKey(day.date))!.start
            var bucket = values[date] ?? Bucket(date: date, seconds: 0, pomodoros: 0)
            bucket.seconds += day.focusSeconds
            bucket.pomodoros += day.pomodoros
            values[date] = bucket
        }
        return values.values.sorted { $0.date < $1.date }
    }

    private func trend(_ summary: HistorySummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("专注趋势").font(.headline)
                Spacer()
                Text(summary.days.count > 90 ? "按月统计" : summary.days.count > 14 ? "按周统计" : "按天统计")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Chart(buckets(summary)) { item in
                BarMark(x: .value("日期", item.date, unit: summary.days.count > 90 ? .month : summary.days.count > 14 ? .weekOfYear : .day),
                        y: .value("小时", Double(item.seconds) / 3600))
                    .foregroundStyle(Theme.accent).cornerRadius(4)
                    .accessibilityLabel(item.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(hours(Double(item.seconds))) 小时，\(item.pomodoros) 个番茄钟")
            }
            .chartYAxisLabel("小时").frame(height: 180)
            .accessibilityIdentifier("stats-detail-trend")
            if summary.pomodoros == 0 { Text("所选时间内暂无专注记录").font(.caption).foregroundStyle(Theme.textSecondary) }
        }.padding(22).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func taskDistribution(_ summary: HistorySummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("任务投入分布").font(.headline)
            Text("按专注时长排序 · 每轮按任务份额分摊").font(.caption).foregroundStyle(Theme.textSecondary)
            if summary.tasks.isEmpty { Text("暂无任务投入记录").foregroundStyle(Theme.textSecondary) }
            ForEach(Array(summary.tasks.prefix(10).enumerated()), id: \.element.id) { index, task in
                VStack(spacing: 7) {
                    HStack {
                        Text(task.title).lineLimit(1)
                        Spacer()
                        Text("\(hours(task.seconds)) 小时 · \(percent(task.seconds, summary))%")
                            .foregroundStyle(Theme.textSecondary)
                    }.font(.system(size: 11))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.04))
                            Capsule().fill(colors[index % colors.count]).frame(width: geometry.size.width * min(1, task.seconds / Double(max(1, summary.focusSeconds))))
                        }
                    }.frame(height: 5)
                    Text("\(String(format: "%.2f", task.pomodoros)) 个番茄份额")
                        .font(.system(size: 10)).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if summary.tasks.count > 10 { Text("展示投入最多的 10 件任务，占比以全部专注时长计算").font(.caption).foregroundStyle(Theme.textSecondary) }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func projectDistribution(_ summary: HistorySummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("项目投入分布").font(.headline)
            if summary.projects.isEmpty {
                Text("暂无项目投入记录").foregroundStyle(Theme.textSecondary)
            } else {
                Chart(summary.projects) { item in
                    SectorMark(angle: .value("专注秒数", item.seconds), innerRadius: .ratio(0.72), angularInset: 1)
                        .foregroundStyle(by: .value("项目", item.title))
                        .accessibilityLabel(item.title)
                        .accessibilityValue("\(hours(item.seconds)) 小时，\(percent(item.seconds, summary))%")
                }
                .chartForegroundStyleScale(range: colors).chartLegend(.hidden).frame(height: 155)
                .accessibilityIdentifier("stats-detail-projects")
                ForEach(Array(summary.projects.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Circle().fill(colors[index % colors.count]).frame(width: 7, height: 7)
                        Text(item.title).lineLimit(1)
                        Spacer()
                        Text("\(percent(item.seconds, summary))% · \(hours(item.seconds)) 小时").foregroundStyle(Theme.textSecondary)
                    }.font(.system(size: 11))
                }
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func records(_ summary: HistorySummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup("专注明细（\(summary.pomodoros) 条）", isExpanded: $recordsExpanded) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(summary.days.filter { !$0.records.isEmpty }) { day in
                        Text(day.date).font(.headline).padding(.vertical, 14)
                        ForEach(day.records) { record in
                            HStack(alignment: .top) {
                                Text(record.startedAt).font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 170, alignment: .leading)
                                Text(record.tasks.isEmpty ? "未分配记录" : record.tasks.map(\.title).joined(separator: "、"))
                                Spacer()
                                Text("\(record.durationSec / 60) 分钟").foregroundStyle(Theme.textSecondary)
                            }.font(.system(size: 12)).padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
            }.accessibilityIdentifier("stats-detail-records")
        }.padding(22).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func hours(_ seconds: Double) -> String { String(format: "%.1f", seconds / 3600) }
    private func percent(_ seconds: Double, _ summary: HistorySummary) -> Int {
        Int((seconds / Double(max(1, summary.focusSeconds)) * 100).rounded())
    }
    private func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    private func dateFromKey(_ key: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key) ?? Date()
    }
}
