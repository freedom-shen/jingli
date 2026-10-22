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

        startAgentServer()

        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.async {
                FloatingPanelController.shared.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agentServer?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func startAgentServer() {
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.supportDirectory,
                withIntermediateDirectories: true
            )
            let database = try JingliDatabase.onDisk(at: AppPaths.databaseURL)
            let server = AgentServer(database: database)
            try server.start(socketURL: AppPaths.socketURL)
            agentServer = server
        } catch {
            fputs("agent server failed: \(error)\n", stderr)
        }
    }
}
