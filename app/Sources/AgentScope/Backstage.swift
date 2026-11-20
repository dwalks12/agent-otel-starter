import Foundation

/// Something a tool call did that is worth a second look. Each rule is a plain pattern over what
/// Claude Code reports for the call (the command, the file path, the URL): no model, no guessing.
/// A flag is not a verdict. Reading .env can be fine; the point is that you can see it happened.
enum Flag: String, CaseIterable, Identifiable {
    case secrets, network, install, destructive, bypass, tests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .secrets: "Touched a secret"
        case .network: "Reached the network"
        case .install: "Pulled in outside code"
        case .destructive: "Destructive command"
        case .bypass: "Skipped a safeguard"
        case .tests: "Edited a test"
        }
    }

    var why: String {
        switch self {
        case .secrets: "Whatever the tool returned went to the model provider with the next request."
        case .network: "Data can leave the machine, and what comes back can carry instructions."
        case .install: "New code from the internet now runs on this machine."
        case .destructive: "Deletes or rewrites work, and may not be undoable."
        case .bypass: "Turned off a check that exists to stop mistakes."
        case .tests: "When the task is “make the test pass”, changing the test is the cheapest way."
        }
    }

    var icon: String {
        switch self {
        case .secrets: "key.fill"
        case .network: "globe"
        case .install: "shippingbox.fill"
        case .destructive: "trash.fill"
        case .bypass: "shield.slash.fill"
        case .tests: "checkmark.seal"
        }
    }

    /// The rules. Commands are matched case-insensitively.
    static func check(tool: String, input: String?) -> [Flag] {
        let fields = Fields(input)
        let command = fields["command"] ?? fields["full_command"] ?? ""
        let path = fields["file_path"] ?? fields["notebook_path"] ?? fields["path"] ?? ""
        let edits = ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(tool)
        let text = command + " " + path

        var flags: [Flag] = []
        if matches(text, #"(^|[\s/'"=<])\.env(\.(local|production|prod|dev|development))?($|[\s'";|&)])"#)
            || matches(text, #"id_(rsa|ed25519|ecdsa)|\.ssh/|\.aws/credentials|\.netrc|\.npmrc|\.pypirc|\.git-credentials|\.kube/config|\.docker/config\.json|\.pem\b|\bcredentials\.json|\bprintenv\b|^\s*env\s*($|\|)|security\s+find-(generic|internet)-password"#) {
            flags.append(.secrets)
        }
        if ["WebFetch", "WebSearch"].contains(tool) || tool.hasPrefix("mcp__")
            || matches(command, #"\b(curl|wget|ssh|scp|rsync|nc|ncat|telnet|sftp)\b|https?://|\bgit\s+(push|pull|fetch|clone)\b"#) {
            flags.append(.network)
        }
        if matches(command, #"\b(pip3?|uv\s+pip|poetry|npm|pnpm|yarn|bun|brew|cargo|go|gem|apt(-get)?|composer)\s+(install|add|i|get)\b|\b(npx|uvx|pipx\s+run)\s|\|\s*(sudo\s+)?(sh|bash|zsh)\b"#) {
            flags.append(.install)
        }
        if matches(command, #"\brm\s+-[a-z]*[rf]|\bgit\s+reset\s+--hard|\bgit\s+clean\s+-[a-z]*f|\bgit\s+push\b[^|;&]*(--force|\s-f\b)|\bgit\s+(checkout|restore)\s+(--\s+)?\.(\s|$)|\bgit\s+branch\s+-D\b|\bdrop\s+(table|database)\b|\btruncate\s+table\b|\bchmod\s+(-R\s+)?777\b|\bsudo\b|\bmkfs\b|\bdd\s+if="#) {
            flags.append(.destructive)
        }
        if matches(command, #"--no-verify|--no-gpg-sign|dangerously|\bHUSKY=0\b|core\.hooksPath"#)
            || (edits && matches(path, #"\.claude/settings|\.git/hooks/"#)) {
            flags.append(.bypass)
        }
        if edits && matches(path, #"(^|/)(test_[^/]*|[^/]*_test\.[a-z]+|[^/]*\.(test|spec)\.[a-z]+)$|/(tests?|__tests__|spec)/"#) {
            flags.append(.tests)
        }
        return flags
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// The string fields of a tool's JSON input.
private struct Fields {
    private var values: [String: String] = [:]

    init(_ json: String?) {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        values = object.compactMapValues { $0 as? String }
    }

    subscript(_ key: String) -> String? { values[key].flatMap { $0.isEmpty ? nil : $0 } }
}

/// What happened in a session that the person at the keyboard never saw: who approved each tool
/// call, model calls they didn't ask for, and the hooks, plugins and MCP servers that rode along.
struct Backstage {
    /// Tool calls Claude Code let through, and how many of those a person approved at the time.
    var allowed = 0
    var askedYou = 0
    var blocked = 0
    var permissionModes: [String] = []

    /// Model calls that weren't the conversation itself: titles, summaries and other side jobs.
    var sideCalls: [(source: String, calls: Int, usd: Double?)] = []

    var hookRuns = 0
    var hookContextChars = 0
    var plugins: [String] = []
    var mcpServers: [String] = []
    /// Where organization-managed settings came from, e.g. "remote".
    var managedSources: [String] = []

    var sideCallCount: Int { sideCalls.reduce(0) { $0 + $1.calls } }
    var sideCallUSD: Double? {
        let costs = sideCalls.compactMap(\.usd)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    /// The conversation's own model calls. Everything else with a query_source is a side job.
    static let mainSources: Set<String> = ["repl_main_thread", "sdk"]

    static func from(_ events: [RawEvent]) -> Backstage {
        var b = Backstage()
        var modes: Set<String> = [], plugins: Set<String> = [], servers: Set<String> = [], managed: Set<String> = []
        var side: [String: (calls: Int, usd: Double?)] = [:]

        for e in events {
            switch e.name {
            case "tool_decision":
                if e["decision"] == "reject" { b.blocked += 1; continue }
                b.allowed += 1
                if e["source"]?.hasPrefix("user_") == true { b.askedYou += 1 }
                if let mode = e["permission_mode"] { modes.insert(mode) }
            case "api_request":
                guard let source = e["query_source"], !mainSources.contains(source),
                      !source.hasPrefix("repl_main_thread") else { continue }
                var entry = side[source] ?? (0, nil)
                entry.calls += 1
                if let usd = e.number("cost_usd") { entry.usd = (entry.usd ?? 0) + usd }
                side[source] = entry
            case "hook_execution_complete":
                b.hookRuns += Int(e.number("num_hooks") ?? 1)
                b.hookContextChars += Int(e.number("additional_context_chars") ?? 0)
            case "plugin_loaded":
                if let name = e["plugin.name"] { plugins.insert(name) }
            case "mcp_server_connection":
                if let name = e["server_name"], e["status"] == "connected" { servers.insert(name) }
            case "managed_settings_resolved":
                // A JSON array such as ["remote"]; empty when no managed settings apply.
                if let data = e["managed_settings.sources"]?.data(using: .utf8),
                   let sources = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    managed.formUnion(sources)
                }
            default:
                break
            }
        }
        b.permissionModes = modes.sorted()
        b.plugins = plugins.sorted()
        b.mcpServers = servers.sorted()
        b.managedSources = managed.sorted()
        b.sideCalls = side.map { (source: $0.key, calls: $0.value.calls, usd: $0.value.usd) }
            .sorted { ($0.calls, $0.source) > ($1.calls, $1.source) }
        return b
    }
}
