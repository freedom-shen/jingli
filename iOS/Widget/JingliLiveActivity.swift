import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.561, green: 0.659, blue: 0.910)
private let tomato = Color(red: 0.780, green: 0.361, blue: 0.251)

struct JingliLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // 锁屏
            HStack(spacing: 14) {
                ring(state: context.state)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.isPaused ? "已暂停" : "专注中")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(context.attributes.taskTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(context.attributes.taskCount > 1
                         ? "本轮 \(context.attributes.taskCount) 件 · 各 1/\(context.attributes.taskCount)"
                         : "本轮 1 件")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.05, green: 0.05, blue: 0.06))
            .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ring(state: context.state).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.attributes.taskTitle)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(context.state.isPaused ? "已暂停" : "专注中")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state)
                        .font(.system(size: 15, weight: .medium))
                        .monospacedDigit()
                        .padding(.trailing, 4)
                }
            } compactLeading: {
                Circle().fill(tomato).frame(width: 6, height: 6)
            } compactTrailing: {
                countdown(context.state)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            } minimal: {
                Circle().fill(tomato).frame(width: 6, height: 6)
            }
            .keylineTint(tomato)
        }
    }

    @ViewBuilder
    private func ring(state: FocusActivityAttributes.ContentState) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress(state))
                .stroke(tomato, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: state.isPaused ? "pause.fill" : "timer")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
    }

    @ViewBuilder
    private func countdown(_ state: FocusActivityAttributes.ContentState) -> some View {
        if state.isPaused {
            Text(format(state.remainingSeconds))
        } else {
            Text(timerInterval: Date()...max(state.endsAt, Date().addingTimeInterval(1)), countsDown: true)
        }
    }

    private func progress(_ state: FocusActivityAttributes.ContentState) -> Double {
        let total = 25.0 * 60
        return max(0, min(1, Double(state.remainingSeconds) / total))
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

@main
struct JingliWidgets: WidgetBundle {
    var body: some Widget {
        JingliWidget()
        JingliLiveActivity()
    }
}
