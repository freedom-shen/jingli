import SwiftUI
import JingliCore

private struct CellCenterKey: PreferenceKey {
    static var defaultValue: [String: CGPoint] { [:] }

    static func reduce(
        value: inout [String: CGPoint],
        nextValue: () -> [String: CGPoint]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// 长按进入拖动、松手落位的任务网格。只在传入的 tasks 范围内重排，
/// 所以主线 / 临时 / 项目是天然隔离的容器，跨区拖动不可能发生。
struct ReorderableTaskGrid<Card: View>: View {
    @ObservedObject var model: AppModel
    let scope: String
    let columns: [GridItem]
    let tasks: [Task]
    @ViewBuilder let card: (Task) -> Card

    @State private var draggingID: String?
    @State private var dragPoint: CGPoint?
    @State private var centers: [String: CGPoint] = [:]
    @State private var liveTasks: [Task]?

    private let gridSpace = "reorder-grid"

    private var displayedTasks: [Task] { liveTasks ?? tasks }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(displayedTasks) { task in
                card(task)
                    .offset(dragOffset(for: task))
                    .scaleEffect(draggingID == task.id ? 1.04 : 1)
                    .shadow(
                        color: .black.opacity(draggingID == task.id ? 0.45 : 0),
                        radius: draggingID == task.id ? 14 : 0,
                        y: 6
                    )
                    .zIndex(draggingID == task.id ? 1 : 0)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CellCenterKey.self,
                                value: [
                                    task.id: CGPoint(
                                        x: geo.frame(in: .named(gridSpace)).midX,
                                        y: geo.frame(in: .named(gridSpace)).midY
                                    )
                                ]
                            )
                        }
                    )
                    .simultaneousGesture(dragGesture(for: task))
            }
        }
        .coordinateSpace(name: gridSpace)
        .onPreferenceChange(CellCenterKey.self) { centers = $0 }
        .animation(
            .interactiveSpring(response: 0.28, dampingFraction: 0.86),
            value: displayedTasks.map(\.id)
        )
    }

    private func dragGesture(for task: Task) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named(gridSpace)
                )
            )
            .onChanged { value in
                guard tasks.count > 1 else { return }
                switch value {
                case .first(true):
                    draggingID = task.id
                    dragPoint = centers[task.id]
                    liveTasks = tasks
                case let .second(_, drag?):
                    dragPoint = drag.location
                    applyLiveReorder()
                default:
                    break
                }
            }
            .onEnded { _ in
                commit()
            }
    }

    private func dragOffset(for task: Task) -> CGSize {
        guard draggingID == task.id,
              let dragPoint,
              let center = centers[task.id]
        else { return .zero }
        return CGSize(
            width: dragPoint.x - center.x,
            height: dragPoint.y - center.y
        )
    }

    /// 把被拖任务插到指针最近的那张卡片的位置，实时刷新顺序。
    private func applyLiveReorder() {
        guard let draggingID,
              let dragPoint,
              var live = liveTasks,
              let from = live.firstIndex(where: { $0.id == draggingID })
        else { return }

        var nearestIndex: Int?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for (index, item) in live.enumerated() where item.id != draggingID {
            guard let center = centers[item.id] else { continue }
            let dx = center.x - dragPoint.x
            let dy = center.y - dragPoint.y
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        guard let target = nearestIndex, target != from else { return }

        live.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: target > from ? target + 1 : target
        )
        liveTasks = live
    }

    private func commit() {
        defer {
            draggingID = nil
            dragPoint = nil
            liveTasks = nil
        }
        guard let live = liveTasks,
              live.map(\.id) != tasks.map(\.id)
        else { return }
        model.saveTaskOrder(scope: scope, orderedIDs: live.map(\.id))
    }
}
