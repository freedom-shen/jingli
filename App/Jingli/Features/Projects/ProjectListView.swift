import SwiftUI
import JingliCore

struct ProjectListView: View {
    @ObservedObject var model: AppModel

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 220), spacing: 14),
        count: 3
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.projects) { project in
                    projectCard(project)
                }
                temporaryTasksCard
                newProjectCard
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
    }

    private func projectCard(_ project: Project) -> some View {
        Button {
            model.openProject(project.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.projectColor(project.color).opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: "folder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.projectColor(project.color))
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if !project.description.isEmpty {
                        Text(project.description)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Text("\(model.projectTaskCount(project.id)) 个任务")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var temporaryTasksCard: some View {
        Button {
            model.openTemporaryTasks()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.projectColor("slate").opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: "tray")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.projectColor("slate"))
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("临时任务")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("随手记的事放这里，不占主线名额")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Text("\(model.temporaryTaskCount) 个任务")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("temporary-tasks-card")
    }

    private var newProjectCard: some View {
        Button {
            model.openProjectEditor(nil)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                Text("新建项目")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-project-button")
    }
}
