#!/bin/sh
# One command: start ClickHouse + the OTel Collector, then open the AgentScope app.
#   ./run.sh          start everything and open the app
#   ./run.sh --seed   same, plus fake sessions so the app has data straight away
#   ./run.sh down     stop the containers (data is kept; add -v to docker compose down to wipe it)
set -eu
cd "$(dirname "$0")"

say() { printf '\033[1;35m▸\033[0m %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. $2" >&2; exit 1; }; }

if [ "${1:-}" = "down" ]; then docker compose down; exit 0; fi

need docker "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
need swift  "Install Xcode or the Swift toolchain: xcode-select --install"
need jq     "brew install jq"

if ! docker info >/dev/null 2>&1; then
  if [ -d /Applications/Docker.app ]; then
    say "Starting Docker Desktop…"
    open -ga Docker
    i=0; until docker info >/dev/null 2>&1; do i=$((i + 1)); [ $i -gt 90 ] && { echo "Docker did not start" >&2; exit 1; }; sleep 1; done
  else
    echo "Docker is installed but not running. Start it and try again." >&2; exit 1
  fi
fi

say "Starting ClickHouse and the OpenTelemetry Collector…"
docker compose up -d --wait

if [ "${1:-}" = "--seed" ]; then
  say "Seeding demo sessions…"
  scripts/seed.sh
fi

cat <<EOF

  ClickHouse   http://localhost:8123  (scripts/query.sh sql/cost-per-session.sql)
  OTLP         localhost:4317 (gRPC) · localhost:4318 (HTTP)

  Next, in another terminal:
    scripts/install-hooks.sh /path/to/a/repo   stamp commits with their session
    cd /path/to/a/repo && $(pwd)/bin/claude-otel

EOF

say "Building and opening AgentScope (the first build takes a minute)…"
exec swift run -c release --package-path app AgentScope
