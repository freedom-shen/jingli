import WidgetKit
import SwiftUI
import JingliCore

private let appGroup = "group.com.freedom-shen.jingli"

struct JingliEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct JingliProvider: TimelineProvider {
    private var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    func placeholder(in context: Context) -> JingliEntry {
        JingliEntry(date: .now, snapshot: WidgetSnapshot(
            pomodoros: 2, focusMinutes: 50,
            mainTotal: 3, mainOpen: 2, tempOpen: 1,
            nextTitle: "合并现有代码"
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (JingliEntry) -> Void) {
        completion(JingliEntry(date: .now, snapshot: WidgetData.load(containerURL: container)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JingliEntry>) -> Void) {
        let entry = JingliEntry(date: .now, snapshot: WidgetData.load(containerURL: container))
        // 15 分钟后自己再读一次；主 App 写入时也会主动 reload
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct JingliWidgetView: View {
    let entry: JingliEntry

    private var snapshot: WidgetSnapshot {
        entry.snapshot ?? WidgetSnapshot(
            pomodoros: 0, focusMinutes: 0, mainTotal: 0, mainOpen: 0, tempOpen: 0, nextTitle: nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("精力管理 · 今天").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.mainOpen)/\(max(snapshot.mainTotal, 4))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.561, green: 0.659, blue: 0.910))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(snapshot.pomodoros)")
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                Text("个番茄 · \(snapshot.focusMinutes) 分钟")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            if let next = snapshot.nextTitle, !next.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 0.78, green: 0.36, blue: 0.25)).frame(width: 5, height: 5)
                    Text(next).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                }
                .padding(.top, 10)
            } else {
                Text(snapshot.mainTotal == 0 ? "今天还没开始" : "主线都做完了")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.top, 10)
            }

            Spacer(minLength: 0)

            HStack {
                Text("临时任务 \(snapshot.tempOpen) 件").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("打开 App 开始").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct JingliWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JingliTodayWidget", provider: JingliProvider()) { entry in
            if #available(iOS 17.0, *) {
                JingliWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                JingliWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("精力管理")
        .description("今天几个番茄、还剩几件主线。")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct JingliWidgetBundle: WidgetBundle {
    var body: some Widget {
        JingliWidget()
    }
}
