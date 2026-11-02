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

    static func models(session: String) -> String {
        """
        SELECT LogAttributes['model'] AS model, \(tokenColumns)
        FROM otel.otel_logs
        WHERE \(apiRequests) AND LogAttributes['session.id'] = \(quoted(session))
        GROUP BY model
        ORDER BY usd DESC NULLS LAST
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

    /// Session ids come from our own query results, but quote them properly anyway.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
    }
}
