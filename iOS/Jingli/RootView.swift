import SwiftUI

struct RootView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var tab: Tab

    init() {
        // 截图/联调用：-screen=统计 直接打开对应 Tab
        let arg = CommandLine.arguments.first { $0.hasPrefix("-screen=") }
        let name = arg?.dropFirst("-screen=".count).description
        _tab = State(initialValue: name.flatMap(Tab.init(rawValue:)) ?? .today)
    }

    enum Tab: String, CaseIterable {
        case today = "今天", projects = "项目", stats = "统计", settings = "设置"

        var icon: String {
            switch self {
            case .today: return "checklist"
            case .projects: return "folder"
            case .stats: return "chart.bar"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Tokens.bg.ignoresSafeArea()

            Group {
                switch tab {
                case .today:
                    if model.snapshot?.dayStarted == true {
                        TodayView()
                    } else {
                        DayStartView()
                    }
                case .projects:
                    ProjectsView()
                case .stats:
                    StatsView()
                case .settings:
                    SettingsView()
                default:
                    PlaceholderView(title: tab.rawValue)
                }
            }
            .padding(.bottom, 76)

            if model.timer != nil {
                FocusView()
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }

            tabBar
                .opacity(model.timer == nil ? 1 : 0)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(
            get: { model.pendingCompletion != nil },
            set: { if !$0 { model.dismissCompletion() } }
        )) {
            if let completion = model.pendingCompletion {
                CompletionSheet(completion: completion)
                    .presentationDetents([.height(420)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Tokens.bg)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .regular))
                        Text(item.rawValue).font(.system(size: 10))
                    }
                    .foregroundStyle(tab == item ? Tokens.accent : Tokens.text3)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Tokens.bg.opacity(0.70), Tokens.bg],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(Tokens.text)
            Text("M2 待接").font(.footnote).foregroundStyle(Tokens.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
