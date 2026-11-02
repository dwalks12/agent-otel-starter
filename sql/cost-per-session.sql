-- Cost and tokens per Claude Code session.
-- OrNull, not OrZero: a missing cost is unknown, not free. sum() skips NULLs,
-- and `unpriced` counts the calls we know nothing about.
SELECT
    LogAttributes['session.id']                                AS session,
    arrayStringConcat(groupUniqArray(LogAttributes['model']), ', ') AS models,
    count()                                                    AS calls,
    sum(toUInt64OrNull(LogAttributes['input_tokens']))         AS input_tokens,
    sum(toUInt64OrNull(LogAttributes['output_tokens']))        AS output_tokens,
    sum(toUInt64OrNull(LogAttributes['cache_read_tokens']))    AS cache_read_tokens,
    round(sum(toFloat64OrNull(LogAttributes['cost_usd'])), 4)  AS usd,
    countIf(LogAttributes['cost_usd'] = '')                    AS unpriced,
    min(Timestamp)                                             AS started,
    max(Timestamp)                                             AS last_seen
FROM otel.otel_logs
WHERE LogAttributes['event.name'] = 'api_request'
GROUP BY session
ORDER BY last_seen DESC
LIMIT 20;
