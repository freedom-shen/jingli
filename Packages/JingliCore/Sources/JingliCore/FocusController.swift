import Foundation

public protocol ShortcutRunning: Sendable {
    func run(_ name: String) throws
    func list() throws -> [String]
}

public struct ProcessShortcutRunner: ShortcutRunning {
    public init() {}

    public func run(_ name: String) throws {
        let result = try execute(arguments: ["run", name])
        guard result.status == 0 else {
            throw FocusError.shortcutFailed(name, result.output)
        }
    }

    public func list() throws -> [String] {
        let result = try execute(arguments: ["list"])
        guard result.status == 0 else {
            throw FocusError.listFailed(result.output)
        }
        return result.output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func execute(arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public final class FocusController: @unchecked Sendable {
    public static let shared = FocusController()

    private let runner: ShortcutRunning
    private let onName: String
    private let offName: String

    public init(
        runner: ShortcutRunning = ProcessShortcutRunner(),
        onName: String = "Jingli Focus On",
        offName: String = "Jingli Focus Off"
    ) {
        self.runner = runner
        self.onName = onName
        self.offName = offName
    }

    public func enable() throws {
        try runner.run(onName)
    }

    public func disable() throws {
        try runner.run(offName)
    }

    public func isConfigured() -> Bool {
        missingShortcuts().isEmpty
    }

    public func missingShortcuts() -> [String] {
        guard let names = try? runner.list() else {
            return [onName, offName]
        }
        let set = Set(names)
        return [onName, offName].filter { !set.contains($0) }
    }
}

public enum FocusError: Error, LocalizedError {
    case shortcutFailed(String, String)
    case listFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .shortcutFailed(name, message):
            return "shortcut \(name) failed: \(message)"
        case let .listFailed(message):
            return "shortcuts list failed: \(message)"
        }
    }
}
