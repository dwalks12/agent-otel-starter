# agent-otel-starter

See what your coding agents are spending, and doing, on your own machine, with open-source parts:

```
Claude Code ──OTLP──▶ OpenTelemetry Collector ──▶ ClickHouse ◀── AgentScope (SwiftUI app)
     │                                                ▲
     └── git hooks: Agent-Session-Id trailer ─────────┘  cost per commit
```

- **Claude Code** already exports OpenTelemetry: one log record per API request, with tokens and cost, plus one per tool call, hook run, plugin and MCP server.
- The **OpenTelemetry Collector** receives it and writes it into **ClickHouse** (`otel.otel_logs`).
- Two **git hooks** stamp each commit with the session that wrote it, so spend joins to code.
- **AgentScope** is a small macOS app. **Live** has a tokens-per-minute gauge, 24-hour totals and the last hour per minute. **Session** shows one session's full transcript: every prompt, Claude's replies, each tool call with its input and result, and each model call with tokens and cost, plus per-tool stats, models and commits. Its **Behind the scenes** tab shows what you didn't see: tool calls that ran without asking you, model calls outside the conversation, hooks, plugins and MCP servers, and tool calls that match a risk rule. Its **Insights** tab has Claude read the session and suggest what to change so the next one goes better, with a public skill to install when one fits.

Companion to the talk *Tracing coding agents with OpenTelemetry* (AI Tinkerers Calgary). The production version of this idea is [Terma](https://terma.ai).

## Quick start

Needs macOS 14+, Docker Desktop, Xcode or the Swift toolchain, and `jq` (`brew install jq`).

```sh
git clone https://github.com/dwalks12/agent-otel-starter.git
cd agent-otel-starter
./run.sh --seed
```

That starts ClickHouse and the collector in Docker, sends some fake sessions, and opens the app. Drop `--seed` once you have real data.

To show only real sessions, run `./run.sh --fresh`. It wipes everything stored so far (seed data, old sessions, commits), so the app starts empty and fills with the sessions you start from then on. Only sessions launched through `bin/claude-otel` are recorded. `scripts/reset-data.sh` does the same wipe while the app is running.

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
| `run.sh` | The one command: starts the stack, optionally wipes (`--fresh`) or seeds (`--seed`) it, builds and opens the app |
| `docker-compose.yml` | ClickHouse 25.8 and OpenTelemetry Collector contrib 0.130.0, reachable on localhost only |
| `otel/config.yaml` | OTLP in, ClickHouse out |
| `clickhouse/init.sql` | The `otel.agent_commits` table the post-commit hook writes |
| `bin/claude-otel` | Runs `claude` with the OpenTelemetry env vars set |
| `hooks/` | `prepare-commit-msg` adds `Agent-Session-Id`; `post-commit` records the commit |
| `scripts/make-demo.sh` | Creates a demo repo with one failing test, a `.env` with a fake key, and the hooks installed; `--guard` adds a deny rule for `.env` |
| `scripts/reset-data.sh` | Empties the stored sessions, metrics and commits (the tables stay) |
| `scripts/install-hooks.sh` | Installs the hooks and a Claude Code `SessionStart` hook into a repo |
| `scripts/seed.sh` | Fake data; `--live` keeps a session running so the gauge moves |
| `scripts/query.sh` | Runs a `.sql` file against ClickHouse |
| `sql/` | `discover.sql`, `cost-per-session.sql`, `cost-per-commit.sql` |
| `app/` | AgentScope, a SwiftUI app (Swift Package; `swift run` builds it). It creates `otel.session_insights` for the Insights tab |

## Behind the scenes

Claude Code reports more than spend. For each session, the **Behind the scenes** tab shows:

| What | From |
|---|---|
| Tool calls that ran without asking you | `tool_decision`: `source` is `config` (a settings rule, the permission mode or the auto-mode classifier) or `hook`, not a `user_*` answer |
| Model calls outside the conversation | `api_request` whose `query_source` isn't `repl_main_thread` (or `sdk` in print mode): titles, summaries, compaction, subagents |
| Hooks, plugins and MCP servers | `hook_execution_complete`, `plugin_loaded`, `mcp_server_connection` |
| Flagged tool calls | Pattern rules over the command, file path or URL (`app/Sources/AgentScope/Backstage.swift`) |

The flag rules are plain patterns, not a model, and a flag is not a verdict:

| Flag | Matches |
|---|---|
| Touched a secret | `.env`, SSH keys, `~/.aws/credentials`, `.netrc`, `printenv` and similar |
| Reached the network | `curl`, `wget`, `ssh`, URLs, `git push/pull/clone`, WebFetch, WebSearch, MCP tools |
| Pulled in outside code | `pip install`, `npm install`, `npx`, `curl … \| sh` and similar |
| Destructive command | `rm -rf`, `git reset --hard`, `git push --force`, `DROP TABLE`, `sudo` and similar |
| Skipped a safeguard | `--no-verify`, `dangerously…`, edits to `.claude/settings` or `.git/hooks` |
| Edited a test | Edit or Write on `test_*`, `*_test.*`, `*.test.*`, `*.spec.*`, `tests/` |

They need tool details, which `bin/claude-otel` turns on (`OTEL_LOG_TOOL_DETAILS=1`). Claude Code leaves that off by default for a reason: commands and file paths can hold secrets, so treat this database like one.

## Insights

The numbers say what a session cost; they don't say what to do about it. On the **Insights** tab, **Generate insights** has Claude read the session and write one to three changes that would make the next one go better. Each one has:

- the kind of change: a rule for `CLAUDE.md`, a tooling fix, a workflow change, a model change or a better prompt
- what happened, with the events that show it, and what to change
- a prompt to paste into a fresh session in that repo, which makes the change (for a better prompt: your request, rewritten)
- a public skill from [skills.sh](https://skills.sh) to install, when one fits

Every session gets at least one. A real cost comes first (something unsafe, a correction, a repeated failure, wasted spend); a session that went fine gets the improvement most worth making, and the card says it went fine.

How it works (`app/Sources/AgentScope/Insights.swift`):

1. The app turns the session into a digest: its totals, then one numbered line per prompt, reply, model call and tool call.
2. It runs `claude -p` on the digest with a JSON schema for the answer, no tools, and telemetry off, so the review doesn't show up as a session itself. This uses your Claude Code login; there is no API key to set up.
3. For each insight the model also writes a few search words. The app searches skills.sh with them, keeps results with 1,000 installs or more, and reads each one's `SKILL.md` description from GitHub. A second `claude -p` call decides whether one fits; an insight with no fitting skill gets none.
4. The result is stored in `otel.session_insights`, which the app creates. Generating again replaces it.

Things to know:

- It costs money, usually a few cents a session, and only runs when you press the button. `AGENT_OTEL_INSIGHTS_MODEL` picks the model (default `sonnet`).
- The transcript goes to the model, as it did during the session. The search words go to skills.sh; the model is told to keep project names out of them, and nothing checks that.
- Insights are a model's opinion, unlike everything else in the app, which is a query. The prompt and the skill are drafts: read them before you paste or install. A skill is someone else's instructions for your agent.
- Tool output isn't in the telemetry, only inputs and whether the call succeeded, so the model can't see why a command failed.

## Preventing it: in the harness, not the pipeline

Telemetry tells you what happened; it can't stop anything. Claude Code's own permission rules and hooks can, and the block shows up in telemetry as a `tool_decision` with `decision=reject`. `scripts/make-demo.sh --guard` commits this to the demo repo:

```json
{ "permissions": { "deny": ["Read(./.env)", "Read(./.env.*)"] } }
```

Read rules also cover file commands in Bash such as `cat`, `head` and `sed`, but not every way to read a file, so for anything that matters use a `PreToolUse` hook (exit code 2 blocks the call; it reports `source=hook`) or managed settings for the whole organization.

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
- **Better flags.** The rules here are regular expressions over one tool call at a time. In production you'd want rules per team, alerts, and context across calls (read `.env`, then `curl` an outside host).
- **Privacy.** `bin/claude-otel` records prompt text, Claude's replies and tool inputs so the app can show transcripts and flags (Claude Code reports tool output sizes, not their content). Run it with `AGENT_OTEL_CONTENT=0` to record usage only. Telemetry export is user-wide, so this sends every Claude Code session you run with `bin/claude-otel`, from any repo. It all stays on your machine here; before you send it to a shared server, scrub secrets out of it, for example with the collector's `redaction` or `transform` processors.

## Troubleshooting

- **App says it can't reach ClickHouse:** `docker compose ps`; both services should be up. `./run.sh` starts them.
- **No sessions after using Claude Code:** check you launched it via `bin/claude-otel`, then `scripts/query.sh sql/discover.sql`. Collector logs: `docker compose logs otel-collector`.
- **Why `bin/claude-otel` passes `--settings`:** an `env` block in `~/.claude/settings.json` beats your shell environment. If another tool already set up an exporter there, plain `export OTEL_...` lines are silently ignored. Settings passed on the command line rank above user settings, so the wrapper wins. Your other telemetry flags from user settings (for example `OTEL_LOG_USER_PROMPTS`) still apply, and that data stays in your local ClickHouse.
- **Ports in use:** ClickHouse uses 8123 and the collector 4318, both on 127.0.0.1. Change them in `docker-compose.yml` and set `AGENT_OTEL_CLICKHOUSE_URL` and `OTEL_ENDPOINT_OVERRIDE` to match.
- **Generate insights says it couldn't run claude:** the app runs the `claude` on your `PATH`, so start it from a terminal where `claude` works (`./run.sh` does).
- **Behind the scenes shows no flags or commands:** the session wasn't launched through `bin/claude-otel`, or ran with `AGENT_OTEL_CONTENT=0`, so tool inputs weren't recorded.

## License

[Choose one before publishing, e.g. MIT.]
