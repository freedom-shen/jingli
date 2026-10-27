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

public enum AppDefaults {
    /// 偏好设置入口。设置了 JINGLI_SUPPORT_DIR（测试隔离数据目录）的进程
    /// 使用独立 suite，避免测试（dogfood / 快照 / agent spike）污染真实偏好，
    /// 比如把「上一轮任务」写成临时任务 ID。
    public static var current: UserDefaults {
        if ProcessInfo.processInfo.environment["JINGLI_SUPPORT_DIR"] != nil {
            return UserDefaults(suiteName: "com.freedom-shen.jingli.isolated")
                ?? .standard
        }
        return .standard
    }
}
