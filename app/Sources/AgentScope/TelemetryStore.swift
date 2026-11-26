import Foundation
import Observation

/// Polls ClickHouse every two seconds and holds what the views draw.
@MainActor
@Observable
final class TelemetryStore {
    private let client: ClickHouseClient

    var live = Usage.empty
    var totals = Totals.empty
    var perMinute: [MinuteBucket] = []
    var sessions: [SessionRow] = []
    var selectedSessionID: String? { didSet { if selectedSessionID != oldValue { models = []; commits = []; transcript = []; backstage = Backstage(); sessionWatchHits = []; insights = nil; insightsError = nil } } }
    var models: [ModelRow] = []
    var commits: [CommitRow] = []
    var transcript: [TranscriptItem] = []
    var backstage = Backstage()
    /// watchlist.json, read again when it changes.
    var watchlist = Watchlist()
    /// Watchlist hits across every session in the last 7 days, newest first.
    var watchHits: [WatchHit] = []
    var watchHitsBySession: [String: Int] = [:]
    /// Watchlist hits in the selected session, from all of its events.
    var sessionWatchHits: [WatchHit] = []
    /// The stored analysis of the selected session; nil until someone asks for one.
    var insights: SessionInsights?
    /// Sessions being analysed right now.
    var insightsRunning: Set<String> = []
    var insightsError: String?
    private var insightsTableReady = false
    var error: String?
    var lastUpdated: Date?

    init(client: ClickHouseClient) {
        self.client = client
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
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func refresh() async {
        do {
            if !insightsTableReady {
                try await client.execute(Queries.createInsights)
                insightsTableReady = true
            }
            if let fresh = watchlist.reloaded() { watchlist = fresh }
            async let candidates = watchCandidates(needles: watchlist.needles)
            async let live = client.rows(Queries.live, as: Usage.self)
            async let totals = client.rows(Queries.totals, as: Totals.self)
            async let perMinute = client.rows(Queries.perMinute, as: MinuteBucket.self)
            async let sessions = client.rows(Queries.sessions, as: SessionRow.self)
            async let prompts = client.rows(Queries.firstPrompts, as: FirstPrompt.self)
            self.live = try await live.first ?? .empty
            self.totals = try await totals.first ?? .empty
            self.perMinute = try await perMinute
            let titles = Dictionary(try await prompts.map { ($0.sessionID, $0.prompt) }, uniquingKeysWith: { a, _ in a })
            self.sessions = try await sessions.map { var row = $0; row.title = titles[row.sessionID]; return row }
            self.watchHits = watchlist.hits(in: try await candidates)
            self.watchHitsBySession = watchHits.reduce(into: [:]) { $0[$1.sessionID, default: 0] += 1 }

            if selectedSessionID == nil { selectedSessionID = self.sessions.first?.sessionID }
            if let id = selectedSessionID {
                async let models = client.rows(Queries.models(session: id), as: ModelRow.self)
                async let commits = client.rows(Queries.commits(session: id), as: CommitRow.self)
                async let rawEvents = client.rows(Queries.events(session: id), as: RawEvent.self)
                async let insights = client.rows(Queries.insights(session: id), as: SessionInsights.self)
                self.models = try await models
                self.commits = try await commits
                let events = try await rawEvents
                self.transcript = Transcript.build(events)
                self.backstage = Backstage.from(events)
                self.sessionWatchHits = watchlist.hits(in: events)
                let stored = try await insights.first
                // The selection may have moved while the queries ran, and an analysis that just
                // finished is newer than what this query read.
                if selectedSessionID == id, (stored?.generatedAt ?? 0) >= (self.insights?.generatedAt ?? 0).rounded(.down) {
                    self.insights = stored
                }
            }
            error = nil
            lastUpdated = .now
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Events that might match the watchlist; none when the list is empty.
    private func watchCandidates(needles: [String]) async throws -> [RawEvent] {
        needles.isEmpty ? [] : try await client.rows(Queries.watchCandidates(needles: needles), as: RawEvent.self)
    }

    /// Asks Claude to review the selected session, and stores what it writes.
    func generateInsights() async {
        guard let session = selectedSession, !insightsRunning.contains(session.sessionID) else { return }
        let id = session.sessionID
        insightsRunning.insert(id)
        insightsError = nil
        defer { insightsRunning.remove(id) }
        do {
            let result = try await Insights.generate(session: session, transcript: transcript, backstage: backstage, commits: commits)
            try await client.execute(Queries.saveInsights(session: id, result))
            if selectedSessionID == id { insights = result }
        } catch {
            if selectedSessionID == id { insightsError = error.localizedDescription }
        }
    }

    static func niceCeiling(_ value: Double) -> Double {
        let magnitude = pow(10, floor(log10(value)))
        for step in [1.0, 2.0, 2.5, 5.0, 10.0] where step * magnitude >= value { return step * magnitude }
        return 10 * magnitude
    }
}
