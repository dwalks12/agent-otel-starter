# agent-otel-starter

See what your coding agents are spending, on your own machine, with open-source parts:

```
Claude Code ──OTLP──▶ OpenTelemetry Collector ──▶ ClickHouse ◀── AgentScope (SwiftUI app)
     │                                                ▲
     └── git hooks: Agent-Session-Id trailer ─────────┘  cost per commit
```

- **Claude Code** already exports OpenTelemetry: one log record per API request, with tokens and cost.
- The **OpenTelemetry Collector** receives it and writes it into **ClickHouse** (`otel.otel_logs`).
- Two **git hooks** stamp each commit with the session that wrote it, so spend joins to code.
- **AgentScope** is a small macOS app. **Live** has a tokens-per-minute gauge, 24-hour totals and the last hour per minute. **Session** shows one session's full transcript: every prompt, Claude's replies, each tool call with its input and result, and each model call with tokens and cost, plus per-tool stats, models and commits.

Companion to the talk *Tracing coding agents with OpenTelemetry* (AI Tinkerers Calgary). The production version of this idea is [Terma](https://terma.ai).

## Quick start

Needs macOS 14+, Docker Desktop, Xcode or the Swift toolchain, and `jq` (`brew install jq`).

```sh
git clone https://github.com/dwalks12/agent-otel-starter.git
cd agent-otel-starter
./run.sh --seed
```

That starts ClickHouse and the collector in Docker, sends some fake sessions, and opens the app. Drop `--seed` once you have real data.

Then try the demo repo: a tiny shop checkout with one failing test and the hooks already installed.

```sh
scripts/make-demo.sh                        # creates ~/agent-otel-demo (--reset to start over)
cd ~/agent-otel-demo && /path/to/agent-otel-starter/bin/claude-otel
> run test_cart.py and make it pass, then commit the fix
git log -1                                  # the commit ends with Agent-Session-Id: <session>
```

In AgentScope, open the session: the Commits tab shows the fix and the Spend card shows its cost per commit.

To use it on your own code instead:

```sh
scripts/install-hooks.sh ~/code/my-repo
cd ~/code/my-repo && /path/to/agent-otel-starter/bin/claude-otel
```

Sessions show up in the app within about five seconds. `./run.sh down` stops the containers.

## What's in here

| Path | What it does |
|---|---|
| `run.sh` | The one command: starts the stack, optionally seeds it, builds and opens the app |
| `docker-compose.yml` | ClickHouse 25.8 and OpenTelemetry Collector contrib 0.130.0, bound to localhost |
| `otel/config.yaml` | OTLP in (gRPC 4317, HTTP 4318), ClickHouse out |
| `clickhouse/init.sql` | The `otel.agent_commits` table the post-commit hook writes |
| `bin/claude-otel` | Runs `claude` with the OpenTelemetry env vars set |
| `hooks/` | `prepare-commit-msg` adds `Agent-Session-Id`; `post-commit` records the commit |
| `scripts/make-demo.sh` | Creates a demo repo with one failing test and the hooks installed |
| `scripts/install-hooks.sh` | Installs the hooks and a Claude Code `SessionStart` hook into a repo |
| `scripts/seed.sh` | Fake data; `--live` keeps a session running so the gauge moves |
| `scripts/query.sh` | Runs a `.sql` file against ClickHouse |
| `sql/` | `discover.sql`, `cost-per-session.sql`, `cost-per-commit.sql` |
| `app/` | AgentScope, a SwiftUI app (Swift Package; `swift run` builds it) |

## Try the SQL

```sh
scripts/query.sh sql/discover.sql           # which events are arriving
scripts/query.sh sql/cost-per-session.sql
scripts/query.sh sql/cost-per-commit.sql
```

## How the commit join works

1. `install-hooks.sh` adds a Claude Code `SessionStart` hook to the repo's `.claude/settings.local.json`. Claude Code passes the hook a JSON payload with `session_id`; the hook writes it to `.git/agent-session`.
2. `prepare-commit-msg` appends `Agent-Session-Id: <id>` with `git interpret-trailers`.
3. `post-commit` sends the sha, repo, subject and line counts to `otel.agent_commits`.
4. `cost-per-commit.sql` joins commits to sessions on the id.

See it in git: `git log --format='%h %(trailers:key=Agent-Session-Id,valueonly)'`

## Things this starter does not do (on purpose)

It's a demo, kept small enough to read in one sitting. In production you'd want:

- **Attribution by files, not time.** These hooks stamp any commit made while a session is open, including your own work. Record which files each session edited and only stamp commits that touch them.
- **More harnesses.** Codex and Copilot export OpenTelemetry too, with different names for the same things. Normalize each one at the edge, once.
- **Idempotent storage.** Exporters retry. Give events deterministic ids and dedupe them (for example with `ReplacingMergeTree`).
- **Estimated costs that say so.** Sources that report tokens but no cost need a price table, and the result labelled as an estimate. Here, a missing cost is left out and counted, never treated as $0.
- **Privacy.** `bin/claude-otel` records prompt text, Claude's replies and tool inputs so the app can show transcripts (Claude Code reports tool output sizes, not their content). Run it with `AGENT_OTEL_CONTENT=0` to record usage only. Telemetry export is user-wide, so this sends every Claude Code session you run with `bin/claude-otel`, from any repo. It all stays on your machine here; don't point it at a shared server without filtering.

## Troubleshooting

- **App says it can't reach ClickHouse:** `docker compose ps`; both services should be up. `./run.sh` starts them.
- **No sessions after using Claude Code:** check you launched it via `bin/claude-otel`, then `scripts/query.sh sql/discover.sql`. Collector logs: `docker compose logs otel-collector`.
- **Why `bin/claude-otel` passes `--settings`:** an `env` block in `~/.claude/settings.json` beats your shell environment. If another tool already set up an exporter there, plain `export OTEL_...` lines are silently ignored. Settings passed on the command line rank above user settings, so the wrapper wins. Your other telemetry flags from user settings (for example `OTEL_LOG_USER_PROMPTS`) still apply, and that data stays in your local ClickHouse.
- **Ports in use:** ClickHouse uses 8123, the collector 4317 and 4318, all on 127.0.0.1. Change them in `docker-compose.yml` and set `AGENT_OTEL_CLICKHOUSE_URL` / `OTEL_EXPORTER_OTLP_ENDPOINT` to match.

## License

[Choose one before publishing, e.g. MIT.]
