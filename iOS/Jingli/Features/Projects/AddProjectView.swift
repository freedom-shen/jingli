import SwiftUI
import JingliCore

struct AddProjectView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var color = "sage"
    @State private var errorText: String?

    private let colors = ["sage", "amber", "blue", "rose", "violet", "slate"]

    private var names: [String: String] = [
        "sage": "鼠尾草", "amber": "琥珀", "blue": "蓝",
        "rose": "玫瑰", "violet": "紫罗兰", "slate": "石板",
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("", text: $name, prompt: Text("项目名称").foregroundStyle(Tokens.text3))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Tokens.text)
                        .padding(14)
                        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("颜色").font(.system(size: 13)).foregroundStyle(Tokens.text3)
                        HStack(spacing: 10) {
                            ForEach(colors, id: \.self) { item in
                                Button {
                                    color = item
                                } label: {
                                    Circle()
                                        .fill(Tokens.projectColor(item))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle().stroke(Tokens.text,
                                                            lineWidth: color == item ? 2 : 0)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("描述").font(.system(size: 13)).foregroundStyle(Tokens.text3)
                        TextField("", text: $note, prompt: Text("这个项目是干什么的"), axis: .vertical)
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.text)
                            .lineLimit(2...5)
                    }
                    .padding(14)
                    .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))

                    Text("项目里的任务只能当主线用；要记临时任务，去今天页点 +。")
                        .font(.system(size: 11)).foregroundStyle(Tokens.text3)
                        .padding(.horizontal, 4)

                    if let errorText {
                        Text(errorText).font(.system(size: 11.5)).foregroundStyle(Tokens.tomato)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .background(Tokens.bg)
            .navigationTitle("新建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(Tokens.text3)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("addproject.save")
                        .foregroundStyle(canSave ? Tokens.accent : Tokens.text3)
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        do {
            try model.createProject(name: name, description: note, color: color)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
