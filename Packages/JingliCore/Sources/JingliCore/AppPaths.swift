import Foundation

public enum AppPaths {
    public static var supportDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["JINGLI_SUPPORT_DIR"],
           !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jingli", isDirectory: true)
    }

    public static var databaseURL: URL {
        supportDirectory.appendingPathComponent("jingli.sqlite")
    }

    public static var socketURL: URL {
        supportDirectory.appendingPathComponent("agent.sock")
    }

    public static var backupDirectory: URL {
        supportDirectory.appendingPathComponent("Backups", isDirectory: true)
    }
}
