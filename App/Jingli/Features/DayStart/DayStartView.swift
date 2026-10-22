import SwiftUI
import JingliCore

struct DayStartView: View {
    @ObservedObject var model: AppModel
    let snapshot: TodaySnapshot

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 180), spacing: 12),
        count: 4
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("按项目从尚未完成的任务里挑出今天要推进的几件。主线任务最多 4 件。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if snapshot.groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(snapshot.groups) { group in
                            groupSection(group)
                        }
                    }
                }
                .padding(.bottom, 20)
            }

            HStack {
                Text(selectionSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("开启一天") {
                    model.startDay()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.textPrimary)
                .foregroundStyle(Theme.background)
                .disabled(model.selected.isEmpty)
                .accessibilityIdentifier("day-start-button")
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
        .padding(.bottom, 28)
    }

    private var selectionSummary: String {
        if model.selected.isEmpty {
            return "选择任务后，开始今天。"
        }
        return "已选 \(model.selectedMainCount) 件主线 · \(model.selectedTemporaryCount) 件临时"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有可安排的任务")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("点右上角的 + 新建一个任务，或先在项目里添加。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
    }

    private func groupSection(_ group: DayStartGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: group.project == nil ? "tray" : "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Text(group.project?.name ?? "未分类任务")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(group.tasks.count) 件任务")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(group.tasks) { task in
                    TaskCard(
                        task: task,
                        selected: model.selected.contains(task.id),
                        disabled: !model.canSelect(task),
                        onToggleSelection: { model.toggleSelection(task) }
                    )
                }
            }
        }
    }
}
