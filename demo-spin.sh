#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"         # the agent-otel-starter checkout, wherever it lives
demo="$HOME/agent-otel-demo"                  # Demo Home Path to add the commit hooks

"$here/scripts/make-demo.sh" --reset --bait "$@"     # creates ~/agent-otel-demo (--reset to start over; pass --bait or --guard through)
"$here/scripts/install-hooks.sh" "$demo"      # installs the git hooks to project
cd "$demo" && exec "$here/bin/claude-otel"    # opens our version of claude for demo purposes (because i have telemetry already configured on my global instance)
