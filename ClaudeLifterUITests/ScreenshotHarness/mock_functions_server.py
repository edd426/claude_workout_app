#!/usr/bin/env python3
"""Local stand-in for the ClaudeLifter Functions API, for screenshot runs only.

The screenshot tour (`ScreenshotTour.swift`) needs realistic data on screen:
weeks of workouts, the real templates, body weight, reports, a pending inbox
change, an insight, and a Coach reply. The app already has a path that loads
all of that from a server — Settings → Restore from Cloud — so this script
plays the server on 127.0.0.1 and the app is launched with
`-serverURL http://127.0.0.1:<port>` (a UserDefaults argument-domain override;
no app code changes).

NEVER point it at production, and never give the simulator a real API key:
the phone is authoritative and a real push from a simulator would replace the
cloud mirror. This server accepts pushes and throws them away.

Usage:
    python3 -I mock_functions_server.py --snapshot snapshot.json \
        [--inbox calls_templates.json] [--port 8765]

`--snapshot` is a GET /api/sync/snapshot response body (the mirror's
`{revision, serverTime, snapshot}`). `--inbox` is optional: a JSON list of
MCP `update_template` calls (`[{"name": "update_template", "arguments": {...}}]`)
served as awaiting-approval inbox operations. Neither file is committed —
they are personal data. In-progress drafts (no `completedAt`) are dropped
from the snapshot so Home starts idle instead of auto-finishing one.
"""

import argparse
import json
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

INSIGHTS = (
    "[warning] Legs haven't been trained since Mon Oct 19, two weeks ago.\n"
    "[suggestion] You finish 3 of 5 planned exercises on a typical day. "
    "Put the exercise you most want done first.\n"
    "[encouragement] You trained five days a week for most of September."
)

COACH_REPLY = (
    "The rack is taken, so do the Leg Press first and come back to squats if "
    "it frees up.\n\n"
    "**Leg Press, both legs:** 3 x 10-12. You last single-leg pressed 40 kg "
    "x 12, so start both legs around 100 kg and add 10 kg if the first set "
    "feels like 3+ reps in reserve.\n\n"
    "Then Seated Leg Curl (Seat 4, ankle 4, pivot 1) while you watch the rack. "
    "If you run short on time, cut the calf raises, not the hamstrings."
)


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class State:
    def __init__(self, snapshot_path, inbox_path):
        with open(snapshot_path) as f:
            body = json.load(f)
        snap = body["snapshot"]
        snap["workouts"] = [w for w in snap["workouts"] if w.get("completedAt")]
        body["revision"] = max(int(body.get("revision", 1)), 1)
        self.snapshot_body = body
        self.revision = body["revision"]
        self.ops = {}
        if inbox_path:
            with open(inbox_path) as f:
                calls = json.load(f)
            for call in calls:
                if call.get("name") != "update_template":
                    continue
                op_id = str(uuid.uuid4())
                self.ops[op_id] = {
                    "id": op_id,
                    "createdAt": now_iso(),
                    "op": "updateTemplate",
                    "payload": call["arguments"],
                    "requiresApproval": True,
                    "status": "awaitingApproval",
                    "appliedAt": None,
                    "error": None,
                }


class Handler(BaseHTTPRequestHandler):
    state: State = None  # set in main

    def log_message(self, fmt, *args):
        print("%s %s" % (time.strftime("%H:%M:%S"), fmt % args), flush=True)

    def _json(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return {}

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/sync/snapshot":
            return self._json(200, self.state.snapshot_body)
        if url.path == "/api/inbox":
            status = parse_qs(url.query).get("status", ["pending"])[0]
            ops = [o for o in self.state.ops.values() if o["status"] == status]
            return self._json(200, {"operations": ops})
        if url.path == "/api/health":
            return self._json(200, {"status": "ok", "mock": True})
        self._json(404, {"error": "not mocked", "path": url.path})

    def do_POST(self):
        url = urlparse(self.path)
        body = self._body()
        if url.path == "/api/sync/snapshot":
            self.state.revision += 1
            return self._json(200, {
                "revision": self.state.revision,
                "serverTime": now_iso(),
                "counts": {},
            })
        if url.path == "/api/inbox/ack":
            results = []
            counts = {"updated": 0, "unchanged": 0, "notFound": 0, "invalid": 0}
            for r in body.get("results", []):
                op = self.state.ops.get(r["id"])
                if op is None:
                    counts["notFound"] += 1
                    results.append({"id": r["id"], "requestedStatus": r["status"],
                                    "resultingStatus": None, "outcome": "notFound",
                                    "conflict": None})
                    continue
                op["status"] = r["status"]
                counts["updated"] += 1
                results.append({"id": r["id"], "requestedStatus": r["status"],
                                "resultingStatus": r["status"], "outcome": "updated",
                                "conflict": None})
            return self._json(200, {"counts": counts, "results": results})
        if url.path == "/api/chat":
            system = json.dumps(body.get("system", ""))
            text = INSIGHTS if "actionable insights" in system else COACH_REPLY
            return self._stream(text)
        self._json(404, {"error": "not mocked", "path": url.path})

    def _stream(self, text):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()

        def event(obj):
            self.wfile.write(("data: " + json.dumps(obj) + "\n\n").encode())
            self.wfile.flush()

        event({"type": "message_start", "message": {"id": "msg_mock", "role": "assistant"}})
        event({"type": "content_block_start", "index": 0,
               "content_block": {"type": "text", "text": ""}})
        words = text.split(" ")
        for i in range(0, len(words), 4):
            chunk = " ".join(words[i:i + 4]) + (" " if i + 4 < len(words) else "")
            event({"type": "content_block_delta", "index": 0,
                   "delta": {"type": "text_delta", "text": chunk}})
            time.sleep(0.02)
        event({"type": "content_block_stop", "index": 0})
        event({"type": "message_delta", "delta": {"stop_reason": "end_turn"},
               "usage": {"output_tokens": len(words)}})
        event({"type": "message_stop"})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--inbox")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    Handler.state = State(args.snapshot, args.inbox)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("mock functions API on http://127.0.0.1:%d (%d inbox ops)"
          % (args.port, len(Handler.state.ops)), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
