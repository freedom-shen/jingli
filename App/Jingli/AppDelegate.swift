import AppKit
import JingliCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var agentServer: AgentServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--snapshot") {
            SnapshotRunner.runIfRequested()
            return
        }

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        CompletionNotifier.shared.configure()
        startAgentServer()
        runDailyBackup()

        if CommandLine.arguments.contains("--show-panel") {
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
        try? service.dailyBackup()
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
