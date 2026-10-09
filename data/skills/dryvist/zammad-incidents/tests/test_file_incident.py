#!/usr/bin/env python3
"""Tests for scripts/file_incident.py against an in-memory Zammad.

Run: python3 -m unittest discover -s . -p 'test_*.py'
"""
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

_SPEC = importlib.util.spec_from_file_location(
    "file_incident", Path(__file__).resolve().parent.parent / "scripts" / "file_incident.py"
)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError("cannot load scripts/file_incident.py")
fi = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(fi)


class FakeZammad:
    """Exact-phrase title search over live tickets, like Zammad's."""

    def __init__(self):
        self.tickets, self.articles, self.tags = [], [], []

    def __call__(self, method, path, payload=None, query=None):
        payload, query = payload or {}, query or {}
        if path == "tickets/search":
            phrase = query["query"].split('title:"', 1)[1][:-1].replace('\\"', '"')
            return [t for t in self.tickets if phrase in t["title"] and t["state"] != "closed"]
        if path == "users/me":
            return {"login": "agent@example.test"}
        if path == "tickets":
            t = {"id": len(self.tickets) + 1, "number": str(1000 + len(self.tickets)),
                 "title": payload["title"], "state": "new"}
            self.tickets.append(t)
            return t
        if path == "ticket_articles":
            self.articles.append(payload)
            return payload
        if path == "tags/add":
            self.tags.append(payload)
            return True
        raise AssertionError(f"unexpected call {method} {path}")


class FileIncidentTest(unittest.TestCase):
    def setUp(self):
        self.zammad = FakeZammad()
        patcher = mock.patch.object(fi, "api", self.zammad)
        patcher.start()
        self.addCleanup(patcher.stop)
        body = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False)
        body.write("count=12 over 15m")
        body.close()
        self.addCleanup(os.unlink, body.name)
        self.body = body.name

    def run_cli(self, key, summary="ingest stalled"):
        args = ["--key", key, "--summary", summary, "--type", "outage",
                "--resolved-when", "probe:q", "--body-file", self.body]
        with mock.patch("builtins.print") as out:
            self.assertEqual(fi.main(args), 0)
        return out.call_args.args[0]

    def test_second_run_appends_instead_of_creating(self):
        first = self.run_cli("fk:splunk:ingest-stalled:index=firewall")
        second = self.run_cli("FK:Splunk:Ingest-Stalled:index=Firewall", "still stalled")
        self.assertIn('"created"', first)
        self.assertIn('"appended"', second)
        self.assertEqual(len(self.zammad.tickets), 1)
        self.assertEqual(self.zammad.articles[0]["ticket_id"], 1)
        self.assertEqual(len(self.zammad.tags), 2)

    def test_negative_longer_key_or_closed_ticket_creates(self):
        self.run_cli("fk:splunk:ingest-stalled:index=fw-edge")
        self.run_cli("fk:splunk:ingest-stalled:index=fw")
        self.zammad.tickets[1]["state"] = "closed"
        self.run_cli("fk:splunk:ingest-stalled:index=fw")
        self.assertEqual(len(self.zammad.tickets), 3)

    def test_rejects_a_key_without_three_parts(self):
        with self.assertRaises(ValueError):
            fi.normalize_key("fk:splunk:only-two")


if __name__ == "__main__":
    unittest.main()
