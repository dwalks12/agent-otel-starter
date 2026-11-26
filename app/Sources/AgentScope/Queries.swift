import Foundation

/// Every number the app shows comes from one of these queries over the collector's otel.otel_logs table.
/// Token and cost attributes are parsed with ...OrNull: a value the source never sent stays unknown,
/// it never becomes 0.
enum Queries {
    static let apiRequests = "LogAttributes['event.name'] = 'api_request'"

    static let tokenColumns = """
        sum(toUInt64OrNull(LogAttributes['input_tokens']))          AS input,
        sum(toUInt64OrNull(LogAttributes['output_tokens']))         AS output,
        sum(toUInt64OrNull(LogAttributes['cache_read_tokens']))     AS cache_read,
        sum(toUInt64OrNull(LogAttributes['cache_creation_tokens'])) AS cache_write,
        sum(toFloat64OrNull(LogAttributes['cost_usd']))             AS usd,
        countIf(LogAttributes['cost_usd'] = '')                     AS unpriced,
        count()                                                     AS calls
        """

    /// The gauge: everything in the trailing 60 seconds.
    static let live = """
        SELECT \(tokenColumns)
        FROM otel.otel_logs
        WHERE \(apiRequests) AND Timestamp >= now64(9) - INTERVAL 60 SECOND
        """

    static let totals = """
        SELECT \(tokenColumns), uniqExact(LogAttributes['session.id']) AS sessions
        FROM otel.otel_logs
        WHERE \(apiRequests) AND Timestamp >= now64(9) - INTERVAL 24 HOUR
        """

    static let perMinute = """
        SELECT toUnixTimestamp(toStartOfMinute(Timestamp)) AS minute,
               sum(toUInt64OrNull(LogAttributes['input_tokens'])) + sum(toUInt64OrNull(LogAttributes['output_tokens']))
             + sum(toUInt64OrNull(LogAttributes['cache_read_tokens'])) + sum(toUInt64OrNull(LogAttributes['cache_creation_tokens'])) AS tokens
        FROM otel.otel_logs
        WHERE \(apiRequests) AND Timestamp >= now64(9) - INTERVAL 60 MINUTE
        GROUP BY minute
        ORDER BY minute
        """

    static let sessions = """
        SELECT LogAttributes['session.id'] AS session_id,
               arrayStringConcat(arraySort(groupUniqArray(LogAttributes['model'])), ', ') AS models,
               toUnixTimestamp(min(Timestamp)) AS started,
               toUnixTimestamp(max(Timestamp)) AS last_seen,
               \(tokenColumns)
        FROM otel.otel_logs
        WHERE \(apiRequests) AND LogAttributes['session.id'] != ''
        GROUP BY session_id
        ORDER BY last_seen DESC
        LIMIT 200
        """

    /// The first captured prompt of each session: the session's title in the sidebar.
    static let firstPrompts = """
        SELECT LogAttributes['session.id'] AS session_id,
               argMin(LogAttributes['prompt'], Timestamp) AS prompt
        FROM otel.otel_logs
        WHERE LogAttributes['event.name'] = 'user_prompt' AND LogAttributes['prompt'] != ''
          AND Timestamp >= now64(9) - INTERVAL 30 DAY
        GROUP BY session_id
        """

    static func models(session: String) -> String {
        """
        SELECT LogAttributes['model'] AS model, \(tokenColumns)
        FROM otel.otel_logs
        WHERE \(apiRequests) AND LogAttributes['session.id'] = \(quoted(session))
        GROUP BY model
        ORDER BY usd DESC NULLS LAST
        """
    }

    /// Every record of one session, in order: the raw material for the transcript.
    /// Ordered by time, then by Claude Code's own per-process event.sequence.
    static func events(session: String) -> String {
        """
        SELECT toUInt64OrZero(LogAttributes['event.sequence']) AS seq,
               toUnixTimestamp64Milli(Timestamp) AS ts_ms,
               LogAttributes['event.name'] AS ev,
               mapFilter((k, v) -> k NOT LIKE 'user.%' AND k NOT LIKE 'organization.%', LogAttributes) AS attrs
        FROM otel.otel_logs
        WHERE LogAttributes['session.id'] = \(quoted(session))
        ORDER BY ts_ms, seq
        LIMIT 5000
        """
    }

    /// Tool calls and replies from every session in the last 7 days that might match the watchlist.
    /// ClickHouse narrows them with a case-insensitive search for each rule's string; Watchlist.hits makes
    /// the exact call. A tool call's other half (its decision or result) comes along through tool_use_id.
    static func watchCandidates(needles: [String]) -> String {
        let text = "concat(LogAttributes['tool_input'], ' ', LogAttributes['tool_parameters'], ' ', LogAttributes['response'])"
        // multiSearchAny takes at most 255 needles per call.
        let search = stride(from: 0, to: needles.count, by: 200).map { start in
            "multiSearchAnyCaseInsensitiveUTF8(\(text), [\(needles[start..<min(start + 200, needles.count)].map(quoted).joined(separator: ", "))])"
        }.joined(separator: " OR ")
        let recent = """
            LogAttributes['event.name'] IN ('tool_decision', 'tool_result', 'assistant_response')
              AND Timestamp >= now64(9) - INTERVAL 7 DAY
            """
        return """
            SELECT toUInt64OrZero(LogAttributes['event.sequence']) AS seq,
                   toUnixTimestamp64Milli(Timestamp) AS ts_ms,
                   LogAttributes['event.name'] AS ev,
                   mapFilter((k, v) -> k IN ('session.id', 'tool_use_id', 'tool_name', 'decision', 'source', 'success',
                                             'tool_input', 'tool_parameters', 'response'), LogAttributes) AS attrs
            FROM otel.otel_logs
            WHERE \(recent)
              AND ((\(search))
                   OR LogAttributes['tool_use_id'] IN (
                       SELECT LogAttributes['tool_use_id'] FROM otel.otel_logs
                       WHERE \(recent) AND LogAttributes['tool_use_id'] != '' AND (\(search))))
            ORDER BY ts_ms DESC, seq DESC
            LIMIT 2000
            """
    }

    static func commits(session: String) -> String {
        """
        SELECT sha, repo, subject, toUnixTimestamp(committed_at) AS committed_at, files, insertions, deletions
        FROM otel.agent_commits FINAL
        WHERE session_id = \(quoted(session))
        ORDER BY committed_at DESC
        """
    }

    /// The app's own table: the latest analysis of each session (a newer row replaces an older one).
    static let createInsights = """
        CREATE TABLE IF NOT EXISTS otel.session_insights
        (
            session_id   String,
            generated_at DateTime64(3) DEFAULT now64(3),
            model        String,
            usd          Nullable(Float64),
            events       UInt32,
            insights     String
        )
        ENGINE = ReplacingMergeTree(generated_at)
        ORDER BY session_id
        """

    static func insights(session: String) -> String {
        """
        SELECT toUnixTimestamp(generated_at) AS generated_at, model, usd, events, insights
        FROM otel.session_insights FINAL
        WHERE session_id = \(quoted(session))
        """
    }

    /// `insights` is the list as JSON. generated_at is left to its default, so the newest write wins.
    static func saveInsights(session: String, _ result: SessionInsights) throws -> String {
        struct Row: Encodable {
            var session_id: String, model: String, usd: Double?, events: Int, insights: String
        }
        let row = Row(session_id: session, model: result.model, usd: result.usd, events: result.events,
                      insights: String(decoding: try JSONEncoder().encode(result.insights), as: UTF8.self))
        return "INSERT INTO otel.session_insights (session_id, model, usd, events, insights) FORMAT JSONEachRow\n"
            + String(decoding: try JSONEncoder().encode(row), as: UTF8.self)
    }

    /// Session ids come from our own query results, but quote them properly anyway.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
    }
}
