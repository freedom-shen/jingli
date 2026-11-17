import Foundation
import JingliCore

/// 一个工具 = 模型看到的 JSON Schema + 落到 AgentCommandRouter 的方法名。
public struct ToolSpec: @unchecked Sendable {
    public let name: String
    public let summary: String
    public let method: String
    public let schema: [String: Any]

    public init(name: String, summary: String, method: String, schema: [String: Any]) {
        self.name = name
        self.summary = summary
        self.method = method
        self.schema = schema
    }
}

public enum ToolCatalog {
    /// 与 CLI / 手机网页同一套方法，只是换了名字和 schema。
    public static let all: [ToolSpec] = [
        ToolSpec(
            name: "today_get",
            summary: "看今天：已选任务、主线/临时、是否已开始、今日统计。任何操作前先读一次。",
            method: "today",
            schema: object([:], required: [])
        ),
        ToolSpec(
            name: "task_add",
            summary: "新建任务。临时任务默认进今天；项目任务只进项目。用户没说的字段不要猜。",
            method: "task.create",
            schema: object([
                "title": string("任务标题，最多 160 字"),
                "lane": enumeration(["main", "temporary"], "临时任务不占主线名额"),
                "project": string("项目名称（不是 id）；临时任务不能带"),
                "date": string("YYYY-MM-DD，只说「今天」可不传"),
                "estimate": integer("预计几个番茄，1–32；用户没说就不传"),
            ], required: ["title"])
        ),
        ToolSpec(
            name: "task_update",
            summary: "改任务的标题 / 备注 / 预估。只传要改的字段。",
            method: "task.update",
            schema: object([
                "id": string("任务 id"),
                "title": string("新标题"),
                "note": string("备注，最长 1000 字"),
                "estimate": integer("预计番茄数，1–32"),
            ], required: ["id"])
        ),
        ToolSpec(
            name: "task_complete",
            summary: "把任务标记完成。",
            method: "task.complete",
            schema: object(["id": string("任务 id")], required: ["id"])
        ),
        ToolSpec(
            name: "task_list",
            summary: "列出未完成任务；includeDone 为 true 时含已完成。",
            method: "task.list",
            schema: object(["includeDone": boolean("是否包含已完成")], required: [])
        ),
        ToolSpec(
            name: "day_add",
            summary: "把已有任务加进今天。主线占 4 件名额，临时任务不限。",
            method: "day.add",
            schema: object([
                "taskIds": array("任务 id 列表", of: "string"),
            ], required: ["taskIds"])
        ),
        ToolSpec(
            name: "project_list",
            summary: "列出项目和每个项目的任务数。",
            method: "project.list",
            schema: object([:], required: [])
        ),
        ToolSpec(
            name: "stats_history",
            summary: "按天回顾：返回最近 N 天（默认 7 天）每天的番茄数、专注秒数、完成任务和每轮记录。用户问「上周」「最近几天」时用它。",
            method: "stats.history",
            schema: object([
                "days": ["type": "integer", "description": "回溯天数，默认 7", "minimum": 1, "maximum": 90],
                "date": string("截止日期 YYYY-MM-DD，默认今天"),
            ], required: [])
        ),
        ToolSpec(
            name: "stats_today",
            summary: "今天的番茄数、专注分钟、完成任务和每轮记录。",
            method: "stats.today",
            schema: object([:], required: [])
        ),
    ]

    public static func spec(named name: String) -> ToolSpec? {
        all.first { $0.name == name }
    }

    // MARK: - schema helpers

    private static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false,
        ]
    }

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func integer(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description, "minimum": 1, "maximum": 32]
    }

    private static func boolean(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    private static func enumeration(_ values: [String], _ description: String) -> [String: Any] {
        ["type": "string", "enum": values, "description": description]
    }

    private static func array(_ description: String, of type: String) -> [String: Any] {
        ["type": "array", "description": description, "items": ["type": type]]
    }
}

/// 把工具调用落到 AgentCommandRouter；返回给模型看的 JSON 字符串。
public final class ToolRunner: @unchecked Sendable {
    private let router: AgentCommandRouter

    public init(router: AgentCommandRouter) {
        self.router = router
    }

    public func run(name: String, argumentsJSON: String) -> (ok: Bool, output: String) {
        guard let spec = ToolCatalog.spec(named: name) else {
            return (false, #"{"error":"未知工具 \#(name)"}"#)
        }
        guard let data = argumentsJSON.data(using: .utf8) else {
            return (false, #"{"error":"参数不是合法 JSON"}"#)
        }
        let object = try? JSONSerialization.jsonObject(with: data)
        let params = (object as? [String: Any]) ?? [:]
        do {
            let result = try call(spec: spec, params: params)
            return (true, encode(result))
        } catch {
            return (false, encode(["error": error.localizedDescription]))
        }
    }

    private func call(spec: ToolSpec, params: [String: Any]) throws -> Any {
        // task_add 带备注时，先建再补备注（task.create 不直接收 note）
        if spec.name == "task_add", let note = params["note"] as? String, !note.isEmpty {
            var createParams = params
            createParams.removeValue(forKey: "note")
            let created = try router.call(method: spec.method, params: createParams)
            if let payload = created as? [String: Any], let id = payload["id"] as? String {
                _ = try? router.call(method: "task.update", params: ["id": id, "note": note])
            }
            return created
        }
        return try router.call(method: spec.method, params: params)
    }

    private func encode(_ value: Any) -> String {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "{}"
    }
}
