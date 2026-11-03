#!/bin/sh
# Empty every table in the otel database (sessions, metrics, commits). The tables stay.
# After this, AgentScope only shows sessions you start from now on.
set -eu
CH_URL="${AGENT_OTEL_CLICKHOUSE_URL:-http://localhost:8123}"
tables="$(curl -sS --fail-with-body "$CH_URL/" --data-binary "SELECT name FROM system.tables WHERE database = 'otel' AND engine NOT LIKE '%View%'")"
for t in $tables; do
  curl -sS --fail-with-body "$CH_URL/" --data-binary "TRUNCATE TABLE otel.\`$t\`"
done
echo "Cleared: $(echo $tables)"
