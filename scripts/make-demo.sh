#!/bin/sh
# Create a tiny git repo with one failing test and the session-stamping hooks installed,
# ready for a live demo: ask Claude Code to fix it, commit, and watch the cost land on the commit.
# Usage: scripts/make-demo.sh [path]          default path: ~/agent-otel-demo
#        scripts/make-demo.sh --reset [path]  delete it first and start over
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
reset=0
if [ "${1:-}" = "--reset" ]; then reset=1; shift; fi
demo="${1:-$HOME/agent-otel-demo}"

command -v python3 >/dev/null || { echo "python3 is required (xcode-select --install)" >&2; exit 1; }

if [ -e "$demo" ]; then
  if [ "$reset" = 1 ]; then
    [ -d "$demo/.git" ] || { echo "$demo exists and is not a git repo; not deleting it" >&2; exit 1; }
    rm -rf "$demo"
  else
    echo "$demo already exists. Use --reset to start over, or pass another path." >&2; exit 1
  fi
fi

mkdir -p "$demo"
cd "$demo"
git init -q -b main

cat > cart.py <<'EOF'
"""Checkout maths for a small online shop."""


def total(subtotal: float, discount: float, tax_rate: float) -> float:
    """Order total. Discounts come off the price before tax is added."""
    return round(subtotal * (1 + tax_rate) - discount, 2)
EOF

cat > test_cart.py <<'EOF'
"""Run with: python3 test_cart.py"""
from cart import total

cases = [
    # subtotal, discount, tax rate, expected total
    (100.00, 10.00, 0.05, 94.50),
    (59.99, 0.00, 0.05, 62.99),
    (20.00, 20.00, 0.05, 0.00),
]

failed = 0
for subtotal, discount, tax_rate, expected in cases:
    got = total(subtotal, discount, tax_rate)
    if got != expected:
        failed += 1
        print(f"FAIL total({subtotal}, {discount}, {tax_rate}) = {got}, expected {expected}")

if failed:
    raise SystemExit(f"{failed} of {len(cases)} checks failed")
print(f"ok: {len(cases)} checks passed")
EOF

cat > README.md <<'EOF'
# agent-otel-demo

A tiny shop checkout with one bug, for demoing agent-otel-starter.

    python3 test_cart.py

Try asking Claude Code: "run test_cart.py and make it pass, then commit the fix".
EOF

printf '__pycache__/\n' > .gitignore
git add .
git -c user.name="${GIT_AUTHOR_NAME:-Demo}" -c user.email="${GIT_AUTHOR_EMAIL:-demo@example.com}" \
  commit -q -m "Add checkout total and tests"

"$here/scripts/install-hooks.sh" "$demo" >/dev/null

echo "Demo repo ready at $demo"
echo
python3 test_cart.py || true
echo
echo "Next:"
echo "  cd $demo"
echo "  $here/bin/claude-otel"
echo "  > run test_cart.py and make it pass, then commit the fix"
echo
echo "Then: git log -1 shows the Agent-Session-Id trailer, and AgentScope shows the commit."
