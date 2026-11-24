import AppKit
import JingliCore
import JingliAgentSocket
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let backupLog = Logger(
        subsystem: "com.freedom-shen.jingli",
        category: "backup"
    )

    private var agentServer: AgentServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 「新的一天」的起点来自设置，DayKey 全局使用。
        DayKey.startHour = AppDefaults.current.object(forKey: "jingli.dayStartHour") as? Int ?? 8

        if CommandLine.arguments.contains("-ckcheck") {
            _Concurrency.Task { await CloudKitCheck.run() }
        }

        if CommandLine.arguments.contains("--snapshot") {
            SnapshotRunner.runIfRequested()
            return
        }

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        // 主窗口关闭后保留对象，浮窗点大圆 / 菜单栏「打开精力管理」才能把它唤回；
        // SwiftUI WindowGroup 默认关闭即释放，会导致这些入口静默无效。
        keepMainWindowAlive()

        if let failure = AppServices.shared.startupFailure {
            presentStartupFailure(failure)
            return
        }

        CompletionNotifier.shared.configure()
        startAgentServer()
        configureRemoteWeb()
        runDailyBackup()
        MacSync.shared.configure(database: AppServices.shared.database) {
            // 手机端改/删的东西被拉回来之后，主界面要重新读库才会变。
            AppServices.shared.model.reload()
        }
        AppServices.shared.model.startTicking()

        if CommandLine.arguments.contains("--show-panel")
            || FloatingPanelController.shared.wasVisible {
            DispatchQueue.main.async {
                FloatingPanelController.shared.show()
            }
        }
    }

    /// SwiftUI 的主窗口在这个时点已存在；标记不随关闭释放，
    /// 浮窗点大圆 / 菜单栏「打开精力管理」才能把关闭的主窗口唤回。
    private func keepMainWindowAlive() {
        for window in NSApp.windows
            where !(window is FloatingPanel) && !(window is CompletionPanel) {
            window.isReleasedWhenClosed = false
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 回到前台补一次拉取：后台期间对端可能写过东西
        MacSync.shared.syncNow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        agentServer?.stop()
        AppServices.shared.model.remoteWeb.stop()
        FocusModeCoordinator.shared.endAndWait()
        try? AppServices.shared.store.setSettingValue("focus_owned", nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func runDailyBackup() {
        guard ProcessInfo.processInfo.environment["JINGLI_NO_BACKUP"] != "1" else { return }
        let service = BackupService(
            database: AppServices.shared.database,
            backupDirectory: AppPaths.backupDirectory
        )
        do {
            try service.dailyBackup()
        } catch {
            Self.backupLog.error(
                "daily backup failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func presentStartupFailure(_ failure: StartupFailure) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = failure.title
        alert.informativeText = failure.detail
        alert.addButton(withTitle: "打开数据目录")
        alert.addButton(withTitle: "退出")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(failure.supportDirectory)
        }
        NSApp.terminate(nil)
    }

    private func configureRemoteWeb() {
        // 网页改完数据后让主界面重新读库；回调来自 HTTP 服务线程，切回主线程。
        AppServices.shared.model.remoteWeb.setChangeHandler {
            DispatchQueue.main.async {
                AppServices.shared.model.reload()
            }
        }
        AppServices.shared.model.remoteWeb.startIfEnabled()
    }

    private func startAgentServer() {
        do {
            let server = AgentServer(
                database: AppServices.shared.database,
                focus: AppServices.shared.model,
                onChange: {
                    DispatchQueue.main.async {
                        AppServices.shared.model.reload()
                    }
                }
            )
            try server.start(socketURL: AppPaths.socketURL)
            agentServer = server
        } catch {
            fputs("agent server failed: \(error)\n", stderr)
        }
    }
}
