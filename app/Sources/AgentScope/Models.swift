import Foundation

/// Token and cost sums. Optional means "no record reported this", which is different from 0.
struct Usage: Decodable, Equatable {
    var input: Double?
    var output: Double?
    var cacheRead: Double?
    var cacheWrite: Double?
    var usd: Double?
    var unpriced: Int
    var calls: Int

    enum CodingKeys: String, CodingKey {
        case input, output, usd, unpriced, calls
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }

    static let empty = Usage(unpriced: 0, calls: 0)

    /// All four token kinds; nil only if no record reported any of them.
    var totalTokens: Double? {
        let parts = [input, output, cacheRead, cacheWrite].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
}

struct Totals: Decodable {
    var usage: Usage
    var sessions: Int

    enum CodingKeys: String, CodingKey { case sessions }

    init(from decoder: Decoder) throws {
        usage = try Usage(from: decoder)
        sessions = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .sessions)
    }

    init(usage: Usage, sessions: Int) {
        self.usage = usage
        self.sessions = sessions
    }

    static let empty = Totals(usage: .empty, sessions: 0)
}

struct MinuteBucket: Decodable, Identifiable {
    var minute: TimeInterval
    var tokens: Double?
    var id: TimeInterval { minute }
    var date: Date { Date(timeIntervalSince1970: minute) }
}

struct SessionRow: Decodable, Identifiable, Hashable {
    var sessionID: String
    var models: String
    var started: TimeInterval
    var lastSeen: TimeInterval
    var usage: Usage
    /// Filled in from a separate query; nil when prompts weren't captured.
    var title: String?

    var id: String { sessionID }
    var startedAt: Date { Date(timeIntervalSince1970: started) }
    var lastSeenAt: Date { Date(timeIntervalSince1970: lastSeen) }

    enum CodingKeys: String, CodingKey {
        case models, started
        case sessionID = "session_id"
        case lastSeen = "last_seen"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        models = try c.decode(String.self, forKey: .models)
        started = try c.decode(TimeInterval.self, forKey: .started)
        lastSeen = try c.decode(TimeInterval.self, forKey: .lastSeen)
        usage = try Usage(from: decoder)
    }

    var modelList: [String] { models.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    static func == (a: SessionRow, b: SessionRow) -> Bool { a.sessionID == b.sessionID && a.usage == b.usage && a.title == b.title }
    func hash(into hasher: inout Hasher) { hasher.combine(sessionID) }
}

struct FirstPrompt: Decodable {
    var sessionID: String
    var prompt: String
    enum CodingKeys: String, CodingKey { case prompt, sessionID = "session_id" }
}

struct ModelRow: Decodable, Identifiable {
    var model: String
    var usage: Usage
    var id: String { model }

    enum CodingKeys: String, CodingKey { case model }

    init(from decoder: Decoder) throws {
        model = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .model)
        usage = try Usage(from: decoder)
    }
}

struct CommitRow: Decodable, Identifiable {
    var sha: String
    var repo: String
    var subject: String
    var committedAt: TimeInterval
    var files: Int
    var insertions: Int
    var deletions: Int

    var id: String { sha }
    var date: Date { Date(timeIntervalSince1970: committedAt) }

    enum CodingKeys: String, CodingKey {
        case sha, repo, subject, files, insertions, deletions
        case committedAt = "committed_at"
    }
}
