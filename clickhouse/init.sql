-- Runs once, on the first start of an empty ClickHouse volume.
-- The collector creates otel.otel_logs itself; this adds the git side of the join.
CREATE DATABASE IF NOT EXISTS otel;

-- One row per commit stamped with an Agent-Session-Id trailer (written by hooks/post-commit).
CREATE TABLE IF NOT EXISTS otel.agent_commits
(
    sha          String,
    session_id   String,
    repo         String,
    subject      String,
    committed_at DateTime64(3),
    files        UInt32,
    insertions   UInt32,
    deletions    UInt32
)
ENGINE = ReplacingMergeTree
ORDER BY (repo, sha);
