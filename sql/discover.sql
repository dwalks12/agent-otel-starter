-- Run this first: which event names and services are actually arriving?
-- Names differ between harnesses and between versions of the same harness.
SELECT
    ServiceName,
    LogAttributes['event.name'] AS event_name,
    count()                     AS records,
    max(Timestamp)              AS last_seen
FROM otel.otel_logs
GROUP BY ServiceName, event_name
ORDER BY records DESC;
