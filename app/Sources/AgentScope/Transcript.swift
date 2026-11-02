import Foundation

/// One raw Claude Code log record for a session: its event name and every attribute.
struct RawEvent: Decodable {
    var sequence: UInt64
    var timeMs: Double
    var name: String
    var attrs: [String: String]

    enum CodingKeys: String, CodingKey {
        case sequence = "seq"
        case timeMs = "ts_ms"
        case name = "ev"
        case attrs
    }

    var date: Date { Date(timeIntervalSince1970: timeMs / 1000) }
    subscript(_ key: String) -> String? { attrs[key].flatMap { $0.isEmpty ? nil : $0 } }
    func number(_ key: String) -> Double? { self[key].flatMap(Double.init) }
}

/// A readable line of the session: what the person asked, what Claude did, what it said.
struct TranscriptItem: Identifiable {
    enum Kind {
        /// `text` is nil when the prompt wasn't captured (OTEL_LOG_USER_PROMPTS off).
        case prompt(text: String?, length: Int?)
        case response(text: String?, model: String?, length: Int?)
        case request(model: String, usage: Usage, durationMs: Double?, ttftMs: Double?)
        case tool(Tool)
        case error(message: String, model: String?, status: String?)
        case system(name: String, detail: String)
    }

    struct Tool {
        var name: String
        var summary: String
        var input: String?        // raw JSON, when captured
        var decision: String?     // accept / reject
        var decisionSource: String?
        var success: Bool?        // nil: no result yet, or rejected
        var durationMs: Double?
        var resultBytes: Double?
    }

    var id: String
    var date: Date
    var kind: Kind

    var isSystem: Bool { if case .system = kind { true } else { false } }
}

enum Transcript {
    static let systemEvents: Set<String> = [
        "hook_registered", "hook_execution_start", "hook_execution_complete", "plugin_loaded",
        "mcp_server_connection", "managed_settings_resolved",
    ]

    /// Rebuilds the transcript from a session's records. A tool call arrives as a decision
    /// (allowed or rejected) and, if it ran, a result; both share a tool_use_id and become one item.
    static func build(_ events: [RawEvent]) -> [TranscriptItem] {
        let decisions = Dictionary(events.filter { $0.name == "tool_decision" }.compactMap { e in e["tool_use_id"].map { ($0, e) } },
                                   uniquingKeysWith: { first, _ in first })
        let resultIDs = Set(events.filter { $0.name == "tool_result" }.compactMap { $0["tool_use_id"] })

        return events.compactMap { e -> TranscriptItem? in
            let id = "\(Int(e.timeMs))-\(e.sequence)-\(e.name)"
            switch e.name {
            case "user_prompt":
                return .init(id: id, date: e.date, kind: .prompt(text: e["prompt"] ?? e["prompt_text"],
                                                                 length: e.number("prompt_length").map(Int.init)))
            case "assistant_response":
                return .init(id: id, date: e.date, kind: .response(text: e["response"], model: e["model"],
                                                                   length: e.number("response_length").map(Int.init)))
            case "api_request":
                let usage = Usage(input: e.number("input_tokens"), output: e.number("output_tokens"),
                                  cacheRead: e.number("cache_read_tokens"), cacheWrite: e.number("cache_creation_tokens"),
                                  usd: e.number("cost_usd"), unpriced: e["cost_usd"] == nil ? 1 : 0, calls: 1)
                return .init(id: id, date: e.date, kind: .request(model: e["model"] ?? "unknown model", usage: usage,
                                                                  durationMs: e.number("duration_ms"), ttftMs: e.number("ttft_ms")))
            case "api_error":
                return .init(id: id, date: e.date, kind: .error(message: e["error"] ?? "API error", model: e["model"],
                                                                status: e["status_code"]))
            case "tool_result":
                let decision = e["tool_use_id"].flatMap { decisions[$0] }
                let input = e["tool_input"] ?? e["tool_parameters"] ?? decision?["tool_parameters"]
                let name = e["tool_name"] ?? "Tool"
                return .init(id: id, date: e.date, kind: .tool(.init(
                    name: name, summary: summarize(tool: name, input: input), input: input,
                    decision: decision?["decision"], decisionSource: decision?["source"],
                    success: e["success"].map { $0 == "true" }, durationMs: e.number("duration_ms"),
                    resultBytes: e.number("tool_result_size_bytes"))))
            case "tool_decision":
                // Shown on its own only when the tool never ran (rejected, or still waiting).
                if let toolID = e["tool_use_id"], resultIDs.contains(toolID) { return nil }
                let name = e["tool_name"] ?? "Tool"
                let input = e["tool_parameters"]
                return .init(id: id, date: e.date, kind: .tool(.init(
                    name: name, summary: summarize(tool: name, input: input), input: input,
                    decision: e["decision"], decisionSource: e["source"], success: nil, durationMs: nil, resultBytes: nil)))
            default:
                let detail = e["hook_event"] ?? e["server_name"] ?? e["plugin.name"] ?? ""
                return .init(id: id, date: e.date, kind: .system(name: e.name.replacingOccurrences(of: "_", with: " "), detail: detail))
            }
        }
    }

    /// A one-line description of a tool call: the command, the file, the pattern.
    static func summarize(tool: String, input: String?) -> String {
        guard let input, let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return input ?? "" }
        func string(_ key: String) -> String? { (object[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func file(_ path: String) -> String { path.split(separator: "/").suffix(2).joined(separator: "/") }

        if let command = string("command") ?? string("full_command") ?? string("bash_command") { return command }
        if let path = string("file_path") ?? string("notebook_path") { return file(path) }
        if let pattern = string("pattern") { return string("path").map { "\(pattern)  in \(file($0))" } ?? pattern }
        if let url = string("url") { return url }
        if let query = string("query") { return query }
        if let description = string("description") ?? string("prompt") { return description }
        return object.keys.sorted().first.flatMap { key in (object[key] as? String).map { "\(key): \($0)" } } ?? ""
    }

    static func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return raw }
        return String(decoding: pretty, as: UTF8.self)
    }
}

/// Per-tool totals for a session.
struct ToolStat: Identifiable {
    var name: String
    var calls = 0
    var failures = 0
    var rejected = 0
    var totalMs = 0.0
    var id: String { name }

    static func from(_ items: [TranscriptItem]) -> [ToolStat] {
        var stats: [String: ToolStat] = [:]
        for item in items {
            guard case .tool(let tool) = item.kind else { continue }
            var stat = stats[tool.name] ?? ToolStat(name: tool.name)
            if tool.decision == "reject" { stat.rejected += 1 } else { stat.calls += 1 }
            if tool.success == false { stat.failures += 1 }
            stat.totalMs += tool.durationMs ?? 0
            stats[tool.name] = stat
        }
        return stats.values.sorted { ($0.calls, $0.name) > ($1.calls, $1.name) }
    }
}
