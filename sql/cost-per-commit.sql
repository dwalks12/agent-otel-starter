-- Each stamped commit next to what its session cost.
-- A session can produce several commits, so `session_usd` is the whole session's spend
-- and `usd_per_commit` splits it evenly: an estimate, labelled as one.
WITH sessions AS
(
    SELECT
        LogAttributes['session.id']                       AS session_id,
        sum(toFloat64OrNull(LogAttributes['cost_usd']))   AS usd,
        sum(toUInt64OrNull(LogAttributes['input_tokens'])) + sum(toUInt64OrNull(LogAttributes['output_tokens'])) AS tokens
    FROM otel.otel_logs
    WHERE LogAttributes['event.name'] = 'api_request'
    GROUP BY session_id
)
SELECT
    substring(c.sha, 1, 8)                                   AS commit,
    c.repo,
    c.subject,
    c.insertions,
    c.deletions,
    round(s.usd, 4)                                          AS session_usd,
    round(s.usd / count() OVER (PARTITION BY c.session_id), 4) AS usd_per_commit,
    s.tokens                                                 AS session_tokens
FROM otel.agent_commits AS c FINAL
LEFT JOIN sessions AS s ON s.session_id = c.session_id
ORDER BY c.committed_at DESC
LIMIT 20;
