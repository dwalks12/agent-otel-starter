#!/bin/sh
# Send fake Claude Code telemetry to the collector so the app has something to show.
# Usage: scripts/seed.sh          4 sessions over the last half hour, with full transcripts
#        scripts/seed.sh --live   keep sending a request every 2 s (Ctrl-C to stop)
# The records use the same event names and attributes Claude Code exports; the values are made up.
set -eu
OTLP="${AGENT_OTEL_OTLP_HTTP:-http://localhost:4318}"
SEQ=0

# emit <session> <unix_seconds> <event> [key value]...
emit() {
  sid=$1 ts=$2 name=$3; shift 3
  SEQ=$((SEQ + 1))
  jq -nc --arg sid "$sid" --arg ts "${ts}000000000" --arg name "$name" --arg seq "$SEQ" '
    def kv($k; $v): {key: $k, value: {stringValue: $v}};
    $ARGS.positional as $p |
    {resourceLogs: [{
      resource: {attributes: [kv("service.name"; "claude-code"), kv("service.version"; "seed")]},
      scopeLogs: [{
        scope: {name: "com.anthropic.claude_code.events"},
        logRecords: [{
          timeUnixNano: $ts, observedTimeUnixNano: $ts,
          body: {stringValue: ("claude_code." + $name)},
          attributes: ([kv("event.name"; $name), kv("session.id"; $sid), kv("event.sequence"; $seq)]
            + [range(0; $p | length; 2) as $i | kv($p[$i]; $p[$i + 1])])
        }]
      }]
    }]}' --args "$@" |
  curl -sf -o /dev/null -H 'Content-Type: application/json' --data-binary @- "$OTLP/v1/logs"
}

rand() { awk -v min="$1" -v max="$2" -v seed="$(od -An -N4 -tu4 /dev/urandom)" 'BEGIN { srand(seed); print int(min + rand() * (max - min)) }'; }
uuid() { uuidgen | tr 'A-Z' 'a-z'; }

# cost = tokens x a rough list price per million (input, output, cache read, cache write)
cost() { awk -v m="$1" -v i="$2" -v o="$3" -v r="$4" -v w="$5" 'BEGIN {
  if (m ~ /opus/) { pi=5; po=25; pr=0.5; pw=6.25 } else if (m ~ /haiku/) { pi=1; po=5; pr=0.1; pw=1.25 } else { pi=3; po=15; pr=0.3; pw=3.75 }
  printf "%.6f", (i*pi + o*po + r*pr + w*pw) / 1000000 }'; }

request() { # session model unix_seconds
  i=$(rand 200 4000); o=$(rand 100 2500); r=$(rand 5000 90000); w=$(rand 0 6000); d=$(rand 1500 14000)
  emit "$1" "$3" api_request model "$2" input_tokens "$i" output_tokens "$o" cache_read_tokens "$r" \
    cache_creation_tokens "$w" cost_usd "$(cost "$2" "$i" "$o" "$r" "$w")" duration_ms "$d" ttft_ms "$((d / 4))"
}

tool() { # session unix_seconds name input_json [success]
  id="toolu_$(uuid | tr -d '-' | cut -c1-24)"
  emit "$1" "$2" tool_decision tool_name "$3" tool_use_id "$id" decision accept source config tool_parameters "$4"
  emit "$1" "$2" tool_result tool_name "$3" tool_use_id "$id" success "${5:-true}" duration_ms "$(rand 5 4000)" tool_input "$4"
}

# A session: model, minutes ago it started, how many model calls, then a script of steps.
# Steps: "P|prompt text", "T|Tool|{json}", "F|Tool|{json}" (failed), "X|Tool|{json}" (rejected), "R|reply text"
session() {
  model=$1 ago=$2 calls=$3; shift 3
  sid=$(uuid); now=$(date +%s); start=$((now - ago)); steps=$#; k=0; step=0
  while [ "$k" -lt "$calls" ]; do
    t=$((start + k * ago / calls))
    # spread the transcript steps across the session's calls
    while [ "$step" -lt "$steps" ] && [ $((step * calls / steps)) -le "$k" ]; do
      step=$((step + 1)); eval "s=\${$step}"
      kind=${s%%|*}; rest=${s#*|}
      case "$kind" in
        P) emit "$sid" "$t" user_prompt prompt "$rest" prompt_length "${#rest}" ;;
        R) emit "$sid" "$t" assistant_response model "$model" response "$rest" response_length "${#rest}" ;;
        T) tool "$sid" "$t" "${rest%%|*}" "${rest#*|}" ;;
        F) tool "$sid" "$t" "${rest%%|*}" "${rest#*|}" false ;;
        X) emit "$sid" "$t" tool_decision tool_name "${rest%%|*}" tool_use_id "toolu_rejected$k" decision reject source user_reject tool_parameters "${rest#*|}" ;;
      esac
    done
    request "$sid" "$model" "$t"
    k=$((k + 1)); n=$((n + 1))
  done
}

if [ "${1:-}" = "--live" ]; then
  sid=$(uuid); echo "Live session $sid: one request every 2 s. Ctrl-C to stop."
  emit "$sid" "$(date +%s)" user_prompt prompt "Refactor the payment retry logic and keep the tests green" prompt_length 57
  while :; do request "$sid" claude-opus-5-5 "$(date +%s)"; printf '.'; sleep 2; done
fi

n=0
session claude-opus-5-5 1800 28 \
  'P|The checkout test in cart.test.ts is failing after the discount change. Can you fix it?' \
  'T|Bash|{"command":"npm test -- cart","description":"Run the cart tests"}' \
  'T|Read|{"file_path":"src/cart/cart.ts"}' \
  'T|Grep|{"pattern":"applyDiscount","path":"src"}' \
  'T|Edit|{"file_path":"src/cart/cart.ts","old_string":"total = applyTax(subtotal) - discount","new_string":"total = applyTax(subtotal - discount)"}' \
  'T|Bash|{"command":"npm test -- cart","description":"Re-run the cart tests"}' \
  'R|Fixed. The discount was subtracted after tax, so the expected total was off by the tax on the discount. I now apply it before tax in `cart.ts`; all 14 cart tests pass.'

session claude-sonnet-5-5 1300 18 \
  'P|Add a dark mode toggle to the settings page' \
  'T|Grep|{"pattern":"theme","path":"src/settings"}' \
  'T|Read|{"file_path":"src/settings/Settings.tsx"}' \
  'T|Write|{"file_path":"src/settings/ThemeToggle.tsx"}' \
  'T|Edit|{"file_path":"src/settings/Settings.tsx","old_string":"<NotificationPrefs />","new_string":"<NotificationPrefs />\n<ThemeToggle />"}' \
  'R|Added `ThemeToggle` under Notifications in Settings. It stores the choice in localStorage and follows the system setting until you pick one.'

session claude-opus-5-5 700 22 \
  'P|Why is the /orders endpoint slow in staging?' \
  'T|Bash|{"command":"git log --oneline -5 -- api/orders.go","description":"Recent changes to the orders handler"}' \
  'T|Read|{"file_path":"api/orders.go"}' \
  'T|Grep|{"pattern":"SELECT .* FROM orders","path":"api"}' \
  'F|Bash|{"command":"go test ./api/... -run Orders","description":"Run the orders tests"}' \
  'X|Bash|{"command":"rm -rf build && make","description":"Clean rebuild"}' \
  'T|Read|{"file_path":"api/orders_test.go"}' \
  'R|The handler loads each order’s line items in a loop, one query per order (an N+1). With 200 orders per page that is 201 queries. Batch it with `WHERE order_id IN (...)`; want me to make that change?'

session claude-haiku-5-5 240 12 \
  'P|Write a commit message for my staged changes' \
  'T|Bash|{"command":"git diff --cached --stat","description":"Summarize staged changes"}' \
  'R|fix(cart): apply discounts before tax'

echo "Sent $n model calls with transcripts across 4 sessions."
