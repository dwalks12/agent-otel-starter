#!/bin/sh
# Install the session-stamping hooks into a git repository.
# Usage: scripts/install-hooks.sh /path/to/your/repo   (defaults to the current directory)
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
target="$(cd "${1:-.}" && pwd)"

command -v jq >/dev/null || { echo "jq is required: brew install jq" >&2; exit 1; }
git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || { echo "$target is not a git repository" >&2; exit 1; }

if [ -n "$(git -C "$target" config --get core.hooksPath || true)" ]; then
  echo "$target sets core.hooksPath; add hooks/prepare-commit-msg and hooks/post-commit there yourself." >&2
  exit 1
fi

hooks_dir="$(cd "$target" && cd "$(git rev-parse --git-common-dir)" && pwd)/hooks"
mkdir -p "$hooks_dir"
for h in prepare-commit-msg post-commit; do
  if [ -e "$hooks_dir/$h" ] && ! cmp -s "$here/hooks/$h" "$hooks_dir/$h"; then
    mv "$hooks_dir/$h" "$hooks_dir/$h.before-agent-otel"
    echo "Moved your existing $h to $h.before-agent-otel"
  fi
  cp "$here/hooks/$h" "$hooks_dir/$h"
  chmod +x "$hooks_dir/$h"
done

# A Claude Code SessionStart hook writes the session id where prepare-commit-msg reads it.
# settings.local.json is Claude Code's per-user, uncommitted project settings file.
settings="$target/.claude/settings.local.json"
mkdir -p "$target/.claude"
[ -s "$settings" ] || echo '{}' > "$settings"
cmd='jq -r .session_id > "$(git rev-parse --git-dir)/agent-session"'
tmp="$(mktemp)"
jq --arg cmd "$cmd" '
  .hooks.SessionStart = ((.hooks.SessionStart // [])
    | map(select((.hooks // []) | all(.command != $cmd)))
    + [{hooks: [{type: "command", command: $cmd}]}])
' "$settings" > "$tmp" && mv "$tmp" "$settings"

# Keep the local settings file out of commits without touching the repo's .gitignore.
exclude="$(cd "$target" && cd "$(git rev-parse --git-common-dir)" && pwd)/info/exclude"
mkdir -p "$(dirname "$exclude")"
grep -qxF '.claude/settings.local.json' "$exclude" 2>/dev/null || echo '.claude/settings.local.json' >> "$exclude"

echo "Hooks installed in $target"
echo "Start Claude Code there with: $here/bin/claude-otel"
