import Foundation

/// The policy relay's state: what it redacts, and what it has seen since it started.
struct RelayState: Decodable {
    var policy: [String: String]
    var stats: Stats

    struct Stats: Decodable {
        var records: Int
        var redacted: [String: Int]
        var rejected: Int
        var upstreamErrors: Int
        var lastSeen: Double?

        enum CodingKeys: String, CodingKey {
            case records, redacted, rejected
            case upstreamErrors = "upstream_errors"
            case lastSeen = "last_seen"
        }
    }

    func redacts(_ rule: PolicyRule) -> Bool { policy[rule.id] == "redact" }
}

/// One thing the policy can gate. The ids match the relay's rule names.
struct PolicyRule: Identifiable {
    var id: String
    var title: String
    var detail: String
    var icon: String

    static let all = [
        PolicyRule(id: "prompts", title: "Your prompts", detail: "What you type to Claude", icon: "text.bubble.fill"),
        PolicyRule(id: "responses", title: "Claude’s replies", detail: "The text Claude writes back", icon: "sparkles"),
        PolicyRule(id: "tool_inputs", title: "Tool inputs", detail: "Commands, file paths and arguments passed to tools", icon: "wrench.and.screwdriver.fill"),
        PolicyRule(id: "identity", title: "Your identity", detail: "Email, user, account and organization ids", icon: "person.crop.circle.fill"),
    ]
}

/// Talks to the relay's /policy endpoint.
struct RelayClient: Sendable {
    let baseURL: URL

    func state() async throws -> RelayState {
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: baseURL.appending(path: "policy"), timeoutInterval: 3))
        return try JSONDecoder().decode(RelayState.self, from: data)
    }

    func set(_ rule: String, to mode: String) async throws -> RelayState {
        var request = URLRequest(url: baseURL.appending(path: "policy"), timeoutInterval: 3)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([rule: mode])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(RelayState.self, from: data)
    }
}

/// The value the relay writes in place of a redacted attribute.
let redactedValue = "[redacted]"
