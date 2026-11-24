import SwiftUI
import JingliCore

struct TodayView: View {
    @ObservedObject var model: AppModel
    let snapshot: TodaySnapshot

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 180), spacing: 12),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let remote = model.remoteFocus {
                    remoteFocusBanner(remote)
                }
                section(
                    title: "主线任务",
                    countText: "\(mainTasks.count) / 4",
                    tasks: mainTasks,
                    emptyText: "今天还没有主线任务"
                )
                section(
                    title: "临时任务",
                    countText: "\(temporaryTasks.count) 件",
                    tasks: temporaryTasks,
                    emptyText: "今天还没有临时任务"
                )
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
    }

    /// 另一台设备（手机）正在专注什么 —— 计时器本身不同步，靠 focus_session 的镜像行。
    private func remoteFocusBanner(_ remote: RemoteFocusSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("iPhone 上正在专注")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(remote.remainingText())
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(remote.titleText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent.opacity(0.20))
        )
        .accessibilityIdentifier("today.remoteFocus")
    }

    private var mainTasks: [Task] {
        let fallback = snapshot.todayTasks.filter { $0.lane != "temporary" }
        return model.orderedTasks(
            scope: "today:\(DayKey.make()):main",
            fallback: fallback
        )
    }

    private var temporaryTasks: [Task] {
        let fallback = snapshot.todayTasks.filter { $0.lane == "temporary" }
        return model.orderedTasks(
            scope: "today:\(DayKey.make()):temporary",
            fallback: fallback
        )
    }

    private func section(
        title: String,
        countText: String,
        tasks: [Task],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(countText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            if tasks.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.card)
                    )
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(tasks) { task in
                        TaskCard(
                            task: task,
                            focusState: model.focusState(for: task),
                            addsToRound: model.canAddToRound(task),
                            pomodoroCount: model.creditedPomodoros(for: task),
                            projectName: model.assignedProjectName(for: task),
                            onDone: { model.toggleDone(task) },
                            onPlay: { model.toggleFocus(for: task) }
                        )
                    }
                }
            }
        }
    }
}
