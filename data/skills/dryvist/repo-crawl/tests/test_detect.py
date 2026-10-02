#!/usr/bin/env python3
"""Tests for scripts/detect.py. Each detector gets a positive control (a
planted finding) and a negative control (a clean tree -> zero findings) —
"prove the zero" applies to a detector just as much as a live query: an
empty result from a detector that is silently broken looks identical to one
from a genuinely clean repo.

Run: python3 -m unittest discover -s . -p 'test_*.py'
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import detect  # noqa: E402


def write(root: Path, rel: str, content: str) -> Path:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return p


class DetectorTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()


class TestCronDrift(DetectorTestCase):
    cfg = {"docs_file": "docs/cron-fleet.md", "defaults_file": "defaults/main.yml"}

    def test_drift_detected(self):
        write(self.repo, self.cfg["docs_file"], "| github-triage | */6 * * * * | triage PRs |\n")
        write(self.repo, self.cfg["defaults_file"], '- name: github-triage\n  schedule: "*/15 * * * *"\n')
        findings = detect.detect_cron_drift(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)
        self.assertIn("*/6", findings[0]["evidence"])
        self.assertIn("*/15", findings[0]["evidence"])

    def test_matching_schedule_is_clean(self):
        write(self.repo, self.cfg["docs_file"], "| github-triage | */15 * * * * | triage PRs |\n")
        write(self.repo, self.cfg["defaults_file"], '- name: github-triage\n  schedule: "*/15 * * * *"\n')
        self.assertEqual(detect.detect_cron_drift(self.repo, self.cfg), [])

    def test_missing_files_is_clean(self):
        self.assertEqual(detect.detect_cron_drift(self.repo, self.cfg), [])


class TestFrontmatterMissing(DetectorTestCase):
    cfg = {"globs": ["*.md"], "required_keys": ["title", "description"]}

    def test_missing_key_flagged(self):
        write(self.repo, "page.md", "---\ntitle: Hello\n---\nbody\n")
        findings = detect.detect_frontmatter_missing(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)
        self.assertIn("description", findings[0]["evidence"])

    def test_complete_frontmatter_is_clean(self):
        write(self.repo, "page.md", "---\ntitle: Hello\ndescription: It says hi\n---\nbody\n")
        self.assertEqual(detect.detect_frontmatter_missing(self.repo, self.cfg), [])


class TestBrokenLinks(DetectorTestCase):
    cfg = {"globs": ["*.md"]}

    def test_broken_relative_link_flagged(self):
        write(self.repo, "page.md", "See [other](missing.md) for more.\n")
        findings = detect.detect_broken_links(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["line"], 1)

    def test_valid_link_is_clean(self):
        write(self.repo, "other.md", "target\n")
        write(self.repo, "page.md", "See [other](other.md) for more.\n")
        self.assertEqual(detect.detect_broken_links(self.repo, self.cfg), [])

    def test_external_link_ignored(self):
        write(self.repo, "page.md", "See [docs](https://example.com/x) for more.\n")
        self.assertEqual(detect.detect_broken_links(self.repo, self.cfg), [])


class TestPlaceholderText(DetectorTestCase):
    cfg = {"globs": ["*.md"]}

    def test_todo_flagged(self):
        write(self.repo, "page.md", "Normal line.\nTODO: fill this in.\n")
        findings = detect.detect_placeholder_text(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["line"], 2)

    def test_clean_doc(self):
        write(self.repo, "page.md", "Nothing to see here.\n")
        self.assertEqual(detect.detect_placeholder_text(self.repo, self.cfg), [])


class TestStaleFactToken(DetectorTestCase):
    cfg = {
        "tokens": [{"token": "OLD_TOKEN_NAME", "doc_glob": "docs/*.md", "code_glob": "code/*.yml"}]
    }

    def test_token_gone_from_code_flagged(self):
        write(self.repo, "docs/page.md", "Set OLD_TOKEN_NAME in the environment.\n")
        write(self.repo, "code/role.yml", "other: value\n")
        findings = detect.detect_stale_fact_token(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)
        self.assertIn("OLD_TOKEN_NAME", findings[0]["evidence"])

    def test_token_still_in_code_is_clean(self):
        write(self.repo, "docs/page.md", "Set OLD_TOKEN_NAME in the environment.\n")
        write(self.repo, "code/role.yml", "OLD_TOKEN_NAME: present\n")
        self.assertEqual(detect.detect_stale_fact_token(self.repo, self.cfg), [])


class TestSkillFrontmatter(DetectorTestCase):
    cfg = {"glob": "**/SKILL.md", "required_keys": ["name", "description", "version"]}

    def test_missing_version_flagged(self):
        write(self.repo, "skills/a/SKILL.md", "---\nname: a\ndescription: does a thing\n---\nbody\n")
        findings = detect.detect_skill_frontmatter(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)
        self.assertIn("version", findings[0]["evidence"])

    def test_complete_skill_is_clean(self):
        write(
            self.repo,
            "skills/a/SKILL.md",
            "---\nname: a\ndescription: does a thing\nversion: 1.0.0\n---\nbody\n",
        )
        self.assertEqual(detect.detect_skill_frontmatter(self.repo, self.cfg), [])


class TestAllowlistReview(DetectorTestCase):
    cfg = {"allowlist_file": "allowlist.nix"}

    def test_entry_without_review_flagged(self):
        write(self.repo, "allowlist.nix", '[\n  { target = "dryvist/new-skill"; }\n]\n')
        findings = detect.detect_allowlist_review(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)
        self.assertIn("new-skill", findings[0]["evidence"])

    def test_entry_with_review_record_is_clean(self):
        write(
            self.repo,
            "allowlist.nix",
            '# new-skill was reviewed on 2026-01-01: no credential, bounded calls.\n'
            '[\n  { target = "dryvist/new-skill"; }\n]\n',
        )
        self.assertEqual(detect.detect_allowlist_review(self.repo, self.cfg), [])


class TestContradiction(DetectorTestCase):
    cfg = {
        "rules": [
            {
                "file_a": "a.md",
                "pattern_a": "already present",
                "file_b": "a.md",
                "pattern_b": "mint a token",
                "message": "claims pre-provisioned while describing minting",
            }
        ]
    }

    def test_contradiction_flagged(self):
        write(self.repo, "a.md", "The token is already present.\nTo mint a token, call the API.\n")
        findings = detect.detect_contradiction(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)

    def test_single_claim_is_clean(self):
        write(self.repo, "a.md", "The token is already present.\n")
        self.assertEqual(detect.detect_contradiction(self.repo, self.cfg), [])


class TestStaleArtifacts(DetectorTestCase):
    cfg = {"globs": ["*.bak"], "max_age_days": 30}

    def test_old_file_flagged(self):
        import os
        import time

        p = write(self.repo, "old.bak", "stale\n")
        old = time.time() - 40 * 86400
        os.utime(p, (old, old))
        findings = detect.detect_stale_artifacts(self.repo, self.cfg)
        self.assertEqual(len(findings), 1)

    def test_fresh_file_is_clean(self):
        write(self.repo, "fresh.bak", "new\n")
        self.assertEqual(detect.detect_stale_artifacts(self.repo, self.cfg), [])


class TestRunAndChecklist(DetectorTestCase):
    def test_checklist_json_loads_and_run_emits_json_lines(self):
        checklist_path = Path(__file__).resolve().parent.parent / "checklist.json"
        checklist = json.loads(checklist_path.read_text())
        self.assertIn("checks", checklist)
        ids = [c["id"] for c in checklist["checks"]]
        self.assertEqual(len(ids), len(set(ids)), "duplicate check ids")
        for check in checklist["checks"]:
            for key in (
                "id",
                "title",
                "repos",
                "detect",
                "config",
                "fix_rule",
                "max_diff",
                "forbidden_paths",
                "pr_title",
                "pr_body",
            ):
                self.assertIn(key, check, f"check {check.get('id')} missing '{key}'")
            self.assertIn(check["detect"], detect.DETECTORS, f"check {check['id']} names an unknown detector")

        # A single real check end to end: plant a drift finding and run() it.
        write(self.repo, "docs/cron-fleet.md", "| github-triage | */6 * * * * | triage PRs |\n")
        write(self.repo, "defaults/main.yml", '- name: github-triage\n  schedule: "*/15 * * * *"\n')
        checks = [
            {
                "id": "D1",
                "detect": "cron_drift",
                "config": {"docs_file": "docs/cron-fleet.md", "defaults_file": "defaults/main.yml"},
            }
        ]
        buf = __import__("io").StringIO()
        emitted = detect.run(self.repo, checks, None, "owner/repo", out=buf)
        self.assertEqual(emitted, 1)
        line = json.loads(buf.getvalue().strip())
        self.assertEqual(line["check_id"], "D1")
        self.assertEqual(line["repo"], "owner/repo")


if __name__ == "__main__":
    unittest.main()
