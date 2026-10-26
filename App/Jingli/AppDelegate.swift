import AppKit
import JingliCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let backupLog = Logger(
        subsystem: "com.freedom-shen.jingli",
        category: "backup"
    )

    private var agentServer: AgentServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--snapshot") {
            SnapshotRunner.runIfRequested()
            return
        }

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        if let failure = AppServices.shared.startupFailure {
            presentStartupFailure(failure)
            return
        }

        CompletionNotifier.shared.configure()
        startAgentServer()
        runDailyBackup()
        AppServices.shared.model.startTicking()

        if CommandLine.arguments.contains("--show-panel")
            || FloatingPanelController.shared.wasVisible {
            DispatchQueue.main.async {
                FloatingPanelController.shared.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agentServer?.stop()
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
