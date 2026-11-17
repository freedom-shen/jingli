import SwiftUI
import JingliCore

/// 「开启一天」：按项目分组挑任务，主线最多 4 件，临时不限。
struct DayStartView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var selected: Set<String> = []
    @State private var limitHit = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var groups: [DayStartGroup] { model.snapshot?.groups ?? [] }
    private var allTasks: [JingliCore.Task] { groups.flatMap(\.tasks) }

    private var selectedMainCount: Int {
        allTasks.filter { selected.contains($0.id) && $0.lane == "main" }.count
    }
    private var selectedTempCount: Int {
        allTasks.filter { selected.contains($0.id) && $0.lane == "temporary" }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        groupHeader(group)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(group.tasks) { task in
                                PickCard(
                                    task: task,
                                    tint: tint(for: group),
                                    isSelected: selected.contains(task.id)
                                ) {
                                    toggle(task)
                                }
                            }
                        }
                        .padding(.bottom, 6)
                    }

                    if groups.isEmpty {
                        Text("项目里还没有任务，先去「项目」里加几件。")
                            .font(.footnote).foregroundStyle(Tokens.text3)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            bottomBar
        }
        .task {
            guard CommandLine.arguments.contains("-preselect") else { return }
            for task in allTasks where task.lane == "main" && selected.count < 2 {
                selected.insert(task.id)
            }
        }
        .alert("主线最多 4 件", isPresented: $limitHit) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("今天已经有 \(selectedMainCount) 件主线了。临时任务不占名额。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("开启一天").font(.system(size: 30, weight: .bold)).foregroundStyle(Tokens.text)
                Spacer()
                Button {
                    selected.removeAll()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.text2)
                        .frame(width: 34, height: 34)
                        .background(Tokens.card, in: Circle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("从项目里挑今天要推进的，主线最多 4 件")
                    .font(.system(size: 11.5)).foregroundStyle(Tokens.text3)
                Spacer()
                Text("主线已选 \(selectedMainCount) / 4")
                    .font(.system(size: 11.5))
                    .foregroundStyle(selectedMainCount >= 4 ? Tokens.tomato : Tokens.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func groupHeader(_ group: DayStartGroup) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint(for: group))
                .frame(width: 14, height: 14)
                .overlay(Text(String((group.project?.name ?? "未").prefix(1)))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08)))
            Text(group.project?.name ?? "未分类")
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Tokens.text)
            Text("\(group.tasks.count) 件").font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 9)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("已选 \(selectedMainCount) 件主线 · \(selectedTempCount) 件临时")
                    .font(.system(size: 11.5)).foregroundStyle(Tokens.text3)
                Spacer()
            }
            Button {
                model.startDay(taskIDs: Array(selected))
            } label: {
                Text("开启今天")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(selected.isEmpty ? Tokens.accent.opacity(0.35) : Tokens.accent,
                                in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Tokens.bg.opacity(0.6), Tokens.bg],
                           startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Tokens.line).frame(height: 1)
        }
    }

    private func tint(for group: DayStartGroup) -> Color {
        Tokens.projectColor(group.project?.color ?? "slate")
    }

    private func toggle(_ task: JingliCore.Task) {
        if selected.contains(task.id) {
            selected.remove(task.id)
            return
        }
        if task.lane == "main", selectedMainCount >= 4 {
            limitHit = true
            return
        }
        selected.insert(task.id)
    }
}

private struct PickCard: View {
    let task: JingliCore.Task
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isSelected ? Tokens.text : Tokens.text2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(task.lane == "main" ? "主线" : "临时")
                        .font(.system(size: 9.5))
                        .foregroundStyle(isSelected ? Tokens.accent : Tokens.text3)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (isSelected ? Tokens.accent.opacity(0.18) : Color.white.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(isSelected ? Tokens.accent : Color.clear)
                            .overlay(Circle().stroke(Color.white.opacity(isSelected ? 0 : 0.22)))
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                        }
                    }
                    .frame(width: 19, height: 19)
                }
                .padding(.top, 10)
            }
            .padding(12)
            .frame(minHeight: 86, alignment: .top)
            .background(
                isSelected ? Tokens.accent.opacity(0.14) : Tokens.card,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Tokens.accent.opacity(0.55) : Tokens.line)
            )
        }
        .buttonStyle(.plain)
    }
}
