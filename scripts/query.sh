#!/bin/sh
# Run a SQL file (or inline SQL) against the local ClickHouse and print a table.
# Usage: scripts/query.sh sql/cost-per-session.sql
#        scripts/query.sh "SELECT count() FROM otel.otel_logs"
set -eu
CH_URL="${AGENT_OTEL_CLICKHOUSE_URL:-http://localhost:8123}"
if [ -f "${1:?usage: query.sh <file.sql | SQL>}" ]; then sql="$(cat "$1")"; else sql="$1"; fi
printf '%s FORMAT PrettyCompactMonoBlock' "$(printf '%s' "$sql" | sed -e 's/;[[:space:]]*$//')" |
  curl -sS --fail-with-body --data-binary @- "$CH_URL/"
