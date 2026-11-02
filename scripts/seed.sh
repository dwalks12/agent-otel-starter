#!/bin/sh
# Send fake Claude Code telemetry to the collector so the app has something to show.
# Usage: scripts/seed.sh          a burst of history: 4 sessions over the last half hour
#        scripts/seed.sh --live   keep sending a request every 2 s (Ctrl-C to stop)
# The records use the same shape Claude Code exports; the values are made up.
set -eu
OTLP="${AGENT_OTEL_OTLP_HTTP:-http://localhost:4318}"

send() { # session model unix_seconds input output cache_read cache_write cost duration_ms
  jq -nc --arg sid "$1" --arg model "$2" --arg ts "${3}000000000" \
    --arg in "$4" --arg out "$5" --arg cr "$6" --arg cw "$7" --arg cost "$8" --arg dur "$9" '
    def kv($k; $v): {key: $k, value: {stringValue: $v}};
    {resourceLogs: [{
      resource: {attributes: [kv("service.name"; "claude-code"), kv("service.version"; "seed")]},
      scopeLogs: [{
        scope: {name: "com.anthropic.claude_code.events"},
        logRecords: [{
          timeUnixNano: $ts, observedTimeUnixNano: $ts,
          body: {stringValue: "claude_code.api_request"},
          attributes: [kv("event.name"; "api_request"), kv("session.id"; $sid), kv("model"; $model),
            kv("input_tokens"; $in), kv("output_tokens"; $out), kv("cache_read_tokens"; $cr),
            kv("cache_creation_tokens"; $cw), kv("cost_usd"; $cost), kv("duration_ms"; $dur)]
        }]
      }]
    }]}' |
  curl -sf -o /dev/null -H 'Content-Type: application/json' --data-binary @- "$OTLP/v1/logs"
}

rand() { awk -v min="$1" -v max="$2" -v seed="$(od -An -N4 -tu4 /dev/urandom)" 'BEGIN { srand(seed); print int(min + rand() * (max - min)) }'; }
uuid() { uuidgen | tr 'A-Z' 'a-z'; }

# cost = tokens x a rough list price per million (input, output, cache read, cache write)
cost() { awk -v m="$1" -v i="$2" -v o="$3" -v r="$4" -v w="$5" 'BEGIN {
  if (m ~ /opus/) { pi=5; po=25; pr=0.5; pw=6.25 } else if (m ~ /haiku/) { pi=1; po=5; pr=0.1; pw=1.25 } else { pi=3; po=15; pr=0.3; pw=3.75 }
  printf "%.6f", (i*pi + o*po + r*pr + w*pw) / 1000000 }'; }

one() { # session model unix_seconds
  i=$(rand 200 4000); o=$(rand 100 2500); r=$(rand 5000 90000); w=$(rand 0 6000)
  send "$1" "$2" "$3" "$i" "$o" "$r" "$w" "$(cost "$2" "$i" "$o" "$r" "$w")" "$(rand 1500 14000)"
}

now=$(date +%s)

if [ "${1:-}" = "--live" ]; then
  sid=$(uuid); echo "Live session $sid: one request every 2 s. Ctrl-C to stop."
  while :; do one "$sid" claude-opus-5-5 "$(date +%s)"; printf '.'; sleep 2; done
fi

n=0
for spec in "claude-opus-5-5 1800 28" "claude-sonnet-5-5 1300 18" "claude-opus-5-5 700 22" "claude-haiku-5-5 240 12"; do
  set -- $spec; sid=$(uuid); start=$((now - $2)); calls=$3; k=0
  while [ "$k" -lt "$calls" ]; do
    one "$sid" "$1" $((start + k * $2 / calls)); k=$((k + 1)); n=$((n + 1))
  done
done
echo "Sent $n fake api_request records across 4 sessions."
