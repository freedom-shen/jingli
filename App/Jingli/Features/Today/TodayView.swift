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

    private var mainTasks: [Task] {
        snapshot.todayTasks.filter { $0.lane != "temporary" }
    }

    private var temporaryTasks: [Task] {
        snapshot.todayTasks.filter { $0.lane == "temporary" }
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
                            onDone: { model.toggleDone(task) },
                            onPlay: { model.toggleFocus(for: task) },
                            onDetail: { model.openTaskDetail(task) }
                        )
                    }
                }
            }
        }
    }
}
