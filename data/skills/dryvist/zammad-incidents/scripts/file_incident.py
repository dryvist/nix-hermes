#!/usr/bin/env python3
"""File a Zammad incident keyed on its finding_key: append to the live ticket
that already carries the key, or create one when none does.

Reads ZAMMAD_URL (with or without a trailing /api/v1) and ZAMMAD_API_TOKEN
from the environment. Prints one JSON line: {"action": "appended"|"created",
"id": <id>, "number": "<number>"}. Exits non-zero on any API failure.

  file_incident.py --key fk:splunk:ingest-stalled:index=firewall \
    --summary "index=firewall ingest stalled" --type outage \
    --resolved-when "probe:<bounded query>" --priority 3 \
    --detection-method alert --body-file /tmp/body.txt
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request

LIVE_STATES = '(new OR open OR "pending reminder" OR "pending close")'
KEY_RE = re.compile(r"^fk:[a-z0-9._-]+:[a-z0-9._-]+:[a-z0-9._=,/@+-]+$")


def normalize_key(raw: str) -> str:
    key = re.sub(r"\s+", "-", raw.strip().lower())
    if not key.startswith("fk:"):
        key = "fk:" + key
    if not KEY_RE.match(key):
        raise ValueError(f"finding key {key!r} is not fk:<source>:<rule>:<entity>")
    return key


def escape_phrase(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def api(method: str, path: str, payload=None, query=None):
    base = os.environ["ZAMMAD_URL"].rstrip("/").removesuffix("/api/v1")
    url = f"{base}/api/v1/{path}"
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Token token=" + os.environ["ZAMMAD_API_TOKEN"])
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read() or b"null")


def find_live(key: str):
    found = api("GET", "tickets/search", query={
        "query": f'state.name:{LIVE_STATES} AND title:"{escape_phrase(key)}"',
        "limit": 10, "expand": "true",
    })
    tickets = found if isinstance(found, list) else (found or {}).get("tickets", [])
    # The phrase search also matches longer keys that start with this one.
    for t in tickets:
        title = t.get("title", "") if isinstance(t, dict) else ""
        if title == key or title.startswith(key + " "):
            return t
    return None


def file_incident(args) -> dict:
    key = normalize_key(args.key)
    with open(args.body_file, encoding="utf-8") as fh:
        facts = fh.read().strip()
    live = find_live(key)
    if live:
        api("POST", "ticket_articles", {
            "ticket_id": live["id"], "subject": args.summary, "body": facts,
            "type": "note", "internal": True,
        })
        return {"action": "appended", "id": live["id"], "number": live.get("number")}
    me = api("GET", "users/me")["login"]
    ticket = {
        "title": f"{key} — {args.summary}", "group": "Incidents",
        "priority_id": args.priority, "customer": me,
        "detection_method": args.detection_method,
        "article": {
            "subject": args.summary, "type": "note", "internal": True,
            "body": f"type: {args.type}\nresolved_when: {args.resolved_when}\n\n{facts}",
        },
    }
    if args.source_issue:
        ticket["source_issue"] = args.source_issue
    created = api("POST", "tickets", ticket)
    for tag in ("auto-managed", f"type:{args.type}"):
        api("POST", "tags/add", {"object": "Ticket", "o_id": created["id"], "item": tag})
    return {"action": "created", "id": created["id"], "number": created.get("number")}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="File or append a Zammad incident by finding_key.")
    p.add_argument("--key", required=True)
    p.add_argument("--summary", required=True)
    p.add_argument("--type", required=True, choices=["outage", "weakness", "hygiene"])
    p.add_argument("--resolved-when", required=True)
    p.add_argument("--priority", type=int, default=2, choices=[1, 2, 3, 4])
    p.add_argument("--detection-method", default="agent",
                   choices=["probe", "user-report", "alert", "agent", "other"])
    p.add_argument("--source-issue")
    p.add_argument("--body-file", required=True)
    args = p.parse_args(argv)
    try:
        print(json.dumps(file_incident(args)))
    except (OSError, ValueError, KeyError) as exc:
        print(f"file_incident: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
