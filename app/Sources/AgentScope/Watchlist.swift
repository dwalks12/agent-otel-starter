import Foundation

/// One thing you never want an agent to touch: a URL, an env key, a path, or any string.
struct WatchRule: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case urls, env, paths, text

        var id: String { rawValue }

        var title: String {
            switch self {
            case .urls: "URLs"
            case .env: "Env keys"
            case .paths: "Paths"
            case .text: "Text"
            }
        }

        var icon: String {
            switch self {
            case .urls: "globe"
            case .env: "key.fill"
            case .paths: "folder.fill"
            case .text: "text.quote"
            }
        }

        var how: String {
            switch self {
            case .urls: "anywhere in the call, any case"
            case .env: "the whole name, exact case"
            case .paths: "anywhere in the call, any case; ~/ matches any home folder"
            case .text: "exact, case and all"
            }
        }
    }

    var kind: Kind
    var match: String
    var why: String

    var id: String { "\(kind.rawValue):\(match)" }

    /// The string searched for. "~/.ssh" becomes "/.ssh", so it matches ~/.ssh, $HOME/.ssh and /Users/you/.ssh.
    var needle: String { kind == .paths && match.hasPrefix("~/") ? String(match.dropFirst()) : match }

    func matches(_ text: String) -> Bool {
        switch kind {
        case .urls, .paths:
            text.range(of: needle, options: .caseInsensitive) != nil
        case .env:
            text.range(of: "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: match) + "(?![A-Za-z0-9_])",
                       options: .regularExpression) != nil
        case .text:
            text.contains(match)
        }
    }
}

/// The watchlist: watchlist.json at the repo root, read again whenever it changes. Every rule is
/// matched against each tool call's input (the command, file path, URL) and each reply Claude writes.
struct Watchlist {
    var rules: [WatchRule] = []
    var url: URL
    var error: String?
    private var modified: Date?

    /// run.sh sets AGENT_OTEL_WATCHLIST; otherwise the file is looked for in the current directory.
    static let defaultURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AGENT_OTEL_WATCHLIST"] ?? "watchlist.json")
        .standardizedFileURL

    init(url: URL = defaultURL) {
        self.url = url
        load()
    }

    var needles: [String] { Array(Set(rules.map(\.needle))).sorted() }

    /// A fresh copy if the file changed since it was read, nil if not. Cheap enough to call every refresh.
    func reloaded() -> Watchlist? {
        Self.modificationDate(url) == modified ? nil : Watchlist(url: url)
    }

    private mutating func load() {
        modified = Self.modificationDate(url)
        guard modified != nil else { error = "No watchlist at \(url.path)."; return }
        do {
            guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                error = "watchlist.json should be a JSON object."
                return
            }
            let unknown = object.keys.filter { !$0.hasPrefix("_") && WatchRule.Kind(rawValue: $0) == nil }.sorted()
            if !unknown.isEmpty {
                error = "Ignored \(unknown.joined(separator: ", ")) in watchlist.json: use urls, env, paths or text."
            }
            for kind in WatchRule.Kind.allCases {
                guard let entries = object[kind.rawValue] as? [String: String] else { continue }
                rules += entries.filter { !$0.key.isEmpty }.map { WatchRule(kind: kind, match: $0.key, why: $0.value) }
                    .sorted { $0.match.localizedCaseInsensitiveCompare($1.match) == .orderedAscending }
            }
        } catch {
            self.error = "Couldn’t read watchlist.json: \(error.localizedDescription)"
        }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// A tool call or reply that matched the watchlist.
struct WatchHit: Identifiable {
    enum Outcome: Equatable {
        case ran, failed, waiting, said
        case blocked(by: String?)
    }

    /// The id of the transcript item it points at.
    var id: String
    var sessionID: String
    var date: Date
    /// nil when the match was in Claude's reply.
    var tool: String?
    var summary: String
    var rules: [WatchRule]
    var outcome: Outcome
}

extension Watchlist {
    /// Every tool call and reply in `events` that matches a rule, newest first. A tool call's decision
    /// and result count as one call, and the hit says how it ended.
    func hits(in events: [RawEvent]) -> [WatchHit] {
        guard !rules.isEmpty else { return [] }
        var calls: [String: (decision: RawEvent?, result: RawEvent?)] = [:]
        var hits: [WatchHit] = []

        for e in events {
            switch e.name {
            case "tool_decision", "tool_result":
                let key = (e["session.id"] ?? "") + "/" + (e["tool_use_id"] ?? Transcript.itemID(e))
                var call = calls[key] ?? (nil, nil)
                if e.name == "tool_result" { call.result = call.result ?? e } else { call.decision = call.decision ?? e }
                calls[key] = call
            case "assistant_response":
                guard let text = e["response"] else { continue }
                let matched = rules.filter { $0.matches(text) }
                guard let first = matched.first else { continue }
                hits.append(WatchHit(id: Transcript.itemID(e), sessionID: e["session.id"] ?? "", date: e.date, tool: nil,
                                     summary: Self.excerpt(text, around: first), rules: matched, outcome: .said))
            default:
                continue
            }
        }

        for call in calls.values {
            // The transcript shows the result when there is one, else the decision; point at the same item.
            guard let shown = call.result ?? call.decision else { continue }
            let input = call.result?["tool_input"] ?? call.decision?["tool_parameters"]
            let parameters = call.result?["tool_parameters"] ?? call.decision?["tool_parameters"]
            let matched = rules.filter { rule in [input, parameters].contains { $0.map(rule.matches) ?? false } }
            guard !matched.isEmpty else { continue }
            let name = shown["tool_name"] ?? "Tool"
            let outcome: WatchHit.Outcome =
                call.decision?["decision"] == "reject" ? .blocked(by: call.decision?["source"])
                : call.result == nil ? .waiting
                : call.result?["success"] == "false" ? .failed
                : .ran
            hits.append(WatchHit(id: Transcript.itemID(shown), sessionID: shown["session.id"] ?? "", date: shown.date, tool: name,
                                 summary: Transcript.summary(tool: name, input: input, parameters: parameters),
                                 rules: matched, outcome: outcome))
        }
        return hits.sorted { $0.date > $1.date }
    }

    /// The reply on one line, cut down to the words around the match.
    private static func excerpt(_ text: String, around rule: WatchRule) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let range = flat.range(of: rule.needle, options: .caseInsensitive) else { return String(flat.prefix(160)) }
        let start = flat.index(range.lowerBound, offsetBy: -60, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: 100, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }
}
