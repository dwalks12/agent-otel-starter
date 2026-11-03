"""Policy relay: Claude Code -> relay -> OpenTelemetry Collector -> ClickHouse.

Claude Code sends OTLP/HTTP JSON here instead of to the collector. The relay applies
the current policy to every attribute before forwarding, so anything the policy
redacts never reaches storage. AgentScope reads and changes the policy over HTTP:

    GET  /policy   {"policy": {...}, "rules": {...}, "stats": {...}}
    PUT  /policy   {"prompts": "redact"}   (any subset of the rules; "keep" or "redact")
    POST /v1/logs, /v1/metrics, /v1/traces   OTLP/HTTP JSON, forwarded upstream

Standard library only. Local demo: the policy API has no auth, so it binds to localhost.
"""

import gzip
import json
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = os.environ.get("UPSTREAM", "http://otel-collector:4318").rstrip("/")
POLICY_FILE = os.environ.get("POLICY_FILE", "/data/policy.json")
PORT = int(os.environ.get("PORT", "4318"))
REDACTED = "[redacted]"
MARKER = "policy.redacted"  # added to each log record that had something redacted

# Each rule covers a set of attribute keys, wherever they appear (log records,
# metric data points, resources).
RULES = {
    "prompts": ["prompt", "prompt_text"],
    "responses": ["response"],
    "tool_inputs": ["tool_parameters", "tool_input"],
    "identity": ["user.email", "user.id", "user.account_id", "user.account_uuid", "organization.id"],
}
MODES = ("keep", "redact")

lock = threading.Lock()
stats = {"records": 0, "redacted": {name: 0 for name in RULES}, "rejected": 0, "upstream_errors": 0, "last_seen": None}


def load_policy():
    policy = {name: "keep" for name in RULES}
    try:
        with open(POLICY_FILE) as f:
            saved = json.load(f)
        policy.update({k: v for k, v in saved.items() if k in RULES and v in MODES})
    except (OSError, ValueError):
        pass
    return policy


def save_policy(policy):
    os.makedirs(os.path.dirname(POLICY_FILE), exist_ok=True)
    tmp = POLICY_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(policy, f, indent=2)
    os.replace(tmp, POLICY_FILE)


policy = load_policy()


def redact_attributes(attrs, keys):
    """Replace the value of every attribute whose key is gated. Returns the rules applied."""
    applied = set()
    for kv in attrs:
        rule = keys.get(kv.get("key"))
        if rule:
            kv["value"] = {"stringValue": REDACTED}
            applied.add(rule)
    return applied


def walk(node, keys, counts, is_record=False):
    """Apply the policy to every "attributes" list in an OTLP JSON payload."""
    if isinstance(node, list):
        for item in node:
            walk(item, keys, counts, is_record)
        return
    if not isinstance(node, dict):
        return
    attrs = node.get("attributes")
    if isinstance(attrs, list):
        applied = redact_attributes(attrs, keys)
        for rule in applied:
            counts[rule] = counts.get(rule, 0) + 1
        if is_record and applied:
            attrs.append({"key": MARKER, "value": {"stringValue": ",".join(sorted(applied))}})
    for key, value in node.items():
        if key != "attributes" and isinstance(value, (dict, list)):
            walk(value, keys, counts, is_record=(key == "logRecords"))


def gated_keys():
    with lock:
        return {key: rule for rule, keys in RULES.items() if policy[rule] == "redact" for key in keys}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet: one line per policy change only
        pass

    def reply(self, status, body, content_type="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        data = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.headers.get("Content-Encoding", "").lower() == "gzip":
            data = gzip.decompress(data)
        return data

    def state(self):
        with lock:
            return {"policy": dict(policy), "rules": RULES, "stats": json.loads(json.dumps(stats))}

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, {"ok": True})
        elif self.path == "/policy":
            self.reply(200, self.state())
        else:
            self.reply(404, {"error": "not found"})

    def do_PUT(self):
        global policy
        if self.path != "/policy":
            return self.reply(404, {"error": "not found"})
        try:
            changes = json.loads(self.body())
            assert isinstance(changes, dict)
        except (ValueError, AssertionError):
            return self.reply(400, {"error": "body must be a JSON object like {\"prompts\": \"redact\"}"})
        bad = {k: v for k, v in changes.items() if k not in RULES or v not in MODES}
        if bad:
            return self.reply(400, {"error": f"unknown rule or mode: {bad}", "rules": list(RULES), "modes": MODES})
        with lock:
            policy = {**policy, **changes}
            save_policy(policy)
        print(f"policy changed: {changes}", flush=True)
        self.reply(200, self.state())

    def do_POST(self):
        if self.path not in ("/v1/logs", "/v1/metrics", "/v1/traces"):
            return self.reply(404, {"error": "not found"})
        try:
            raw = self.body()
        except OSError:
            return self.reply(400, {"error": "bad gzip body"})
        # Fail closed: a protobuf payload can't be inspected here, so it isn't forwarded.
        if "json" not in self.headers.get("Content-Type", ""):
            with lock:
                stats["rejected"] += 1
            return self.reply(415, {"error": "this relay accepts OTLP/HTTP JSON only: set OTEL_EXPORTER_OTLP_PROTOCOL=http/json"})
        try:
            payload = json.loads(raw)
        except ValueError:
            return self.reply(400, {"error": "invalid JSON"})

        counts = {}
        walk(payload, gated_keys(), counts)
        records = sum(len(sl.get("logRecords", [])) for rl in payload.get("resourceLogs", []) for sl in rl.get("scopeLogs", []))

        request = urllib.request.Request(UPSTREAM + self.path, data=json.dumps(payload).encode(), method="POST",
                                         headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=10) as upstream:
                status, body = upstream.status, upstream.read()
        except urllib.error.HTTPError as error:
            status, body = error.code, error.read()
        except OSError as error:
            with lock:
                stats["upstream_errors"] += 1
            return self.reply(503, {"error": f"collector unreachable: {error}"})

        with lock:
            stats["records"] += records
            stats["last_seen"] = time.time()
            for rule, n in counts.items():
                stats["redacted"][rule] += n
        self.reply(status, body)


if __name__ == "__main__":
    print(f"relay on :{PORT} -> {UPSTREAM}, policy {policy}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
