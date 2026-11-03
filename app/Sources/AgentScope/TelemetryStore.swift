import Foundation
import Observation

/// Polls ClickHouse every two seconds and holds what the views draw.
@MainActor
@Observable
final class TelemetryStore {
    private let client: ClickHouseClient
    private let relayClient: RelayClient

    var live = Usage.empty
    var totals = Totals.empty
    var perMinute: [MinuteBucket] = []
    var sessions: [SessionRow] = []
    var selectedSessionID: String? { didSet { if selectedSessionID != oldValue { models = []; commits = []; transcript = [] } } }
    var models: [ModelRow] = []
    var commits: [CommitRow] = []
    var transcript: [TranscriptItem] = []
    var error: String?
    var lastUpdated: Date?
    /// nil while the relay can't be reached.
    var relay: RelayState?
    var relayError: String?

    init(client: ClickHouseClient, relay: RelayClient) {
        self.client = client
        self.relayClient = relay
    }

    func refreshRelay() async {
        do { relay = try await relayClient.state(); relayError = nil }
        catch { relay = nil; relayError = error.localizedDescription }
    }

    func setPolicy(_ rule: PolicyRule, redact: Bool) async {
        do { relay = try await relayClient.set(rule.id, to: redact ? "redact" : "keep"); relayError = nil }
        catch { relayError = error.localizedDescription }
    }

    var selectedSession: SessionRow? { sessions.first { $0.sessionID == selectedSessionID } }
    var maxSessionSpend: Double { sessions.compactMap(\.usage.usd).max() ?? 0 }

    /// Tokens per minute over the trailing 60 seconds: the gauge's needle.
    var tokensPerMinute: Double { live.totalTokens ?? 0 }

    /// The gauge's full scale: a round number above the busiest minute of the last hour.
    var gaugeMax: Double {
        let peak = max(perMinute.compactMap(\.tokens).max() ?? 0, tokensPerMinute)
        return Self.niceCeiling(max(peak * 1.15, 50_000))
    }

    func run() async {
        while !Task.isCancelled {
            await refresh()
            await refreshRelay()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func refresh() async {
        do {
            async let live = client.rows(Queries.live, as: Usage.self)
            async let totals = client.rows(Queries.totals, as: Totals.self)
            async let perMinute = client.rows(Queries.perMinute, as: MinuteBucket.self)
            async let sessions = client.rows(Queries.sessions, as: SessionRow.self)
            async let prompts = client.rows(Queries.firstPrompts, as: FirstPrompt.self)
            self.live = try await live.first ?? .empty
            self.totals = try await totals.first ?? .empty
            self.perMinute = try await perMinute
            let titles = Dictionary(try await prompts.map { ($0.sessionID, $0.prompt) }, uniquingKeysWith: { a, _ in a })
            self.sessions = try await sessions.map { var row = $0; row.title = titles[row.sessionID].map { $0 == redactedValue ? "Redacted prompt" : $0 }; return row }

            if selectedSessionID == nil { selectedSessionID = self.sessions.first?.sessionID }
            if let id = selectedSessionID {
                async let models = client.rows(Queries.models(session: id), as: ModelRow.self)
                async let commits = client.rows(Queries.commits(session: id), as: CommitRow.self)
                async let events = client.rows(Queries.events(session: id), as: RawEvent.self)
                self.models = try await models
                self.commits = try await commits
                self.transcript = Transcript.build(try await events)
            }
            error = nil
            lastUpdated = .now
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func niceCeiling(_ value: Double) -> Double {
        let magnitude = pow(10, floor(log10(value)))
        for step in [1.0, 2.0, 2.5, 5.0, 10.0] where step * magnitude >= value { return step * magnitude }
        return 10 * magnitude
    }
}
