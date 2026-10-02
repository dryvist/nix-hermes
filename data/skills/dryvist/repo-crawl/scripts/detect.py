#!/usr/bin/env python3
"""Deterministic finding detector for the repo-crawl skill.

Reads checklist.json and a checked-out target repo, runs exactly the
detector function named by each check's "detect" field, and prints one JSON
object per line to stdout: {"check_id", "repo", "path", "line", "evidence"}.

The model never runs these checks itself — it reads this script's output and
turns at most one finding into a fix (see SKILL.md). That split is the whole
point of "tightly guided": detection is code, not a judgment call.

ponytail: every detector is a plain function over stdlib (pathlib/re/json),
no YAML parser, no network. Good enough for the fixed file shapes
checklist.json configures; a detector whose target repo drifts past what its
config captures is that detector's upgrade trigger, not a reason to reach for
a parsing library.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


def read_frontmatter(path: Path) -> dict | None:
    """Minimal `---\\nkey: value\\n...\\n---` reader. Only flat scalar keys —
    all the SKILL.md/doc frontmatter in scope here uses that shape."""
    text = path.read_text(errors="replace")
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    data: dict[str, str] = {}
    for line in text[3:end].splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
        if m:
            data[m.group(1)] = m.group(2).strip()
    return data


def _rel(repo: Path, p: Path) -> str:
    return str(p.relative_to(repo))


def detect_cron_drift(repo: Path, cfg: dict) -> list[dict]:
    docs_file = repo / cfg["docs_file"]
    defaults_file = repo / cfg["defaults_file"]
    if not docs_file.exists() or not defaults_file.exists():
        return []

    doc_sched: dict[str, tuple[str, int]] = {}
    row_re = re.compile(r"^\|\s*`?([a-zA-Z0-9_-]+)`?\s*\|\s*`?([0-9*/, -]+)`?\s*\|")
    for i, line in enumerate(docs_file.read_text(errors="replace").splitlines(), 1):
        m = row_re.match(line)
        if m:
            doc_sched[m.group(1)] = (m.group(2).strip(), i)

    # Sequential scan of a flat `- name: foo\n  schedule: "..."` list — not a
    # real YAML parser; see module docstring.
    role_sched: dict[str, str] = {}
    cur_name: str | None = None
    for line in defaults_file.read_text(errors="replace").splitlines():
        m = re.match(r"^\s*-?\s*name:\s*(\S+)", line)
        if m:
            cur_name = m.group(1)
            continue
        m = re.match(r'^\s*schedule:\s*"?([^"]+?)"?\s*$', line)
        if m and cur_name:
            role_sched[cur_name] = m.group(1).strip()
            cur_name = None

    findings = []
    for name, (sched, lineno) in doc_sched.items():
        if name in role_sched and role_sched[name] != sched:
            findings.append(
                {
                    "path": cfg["docs_file"],
                    "line": lineno,
                    "evidence": f"docs say {name} runs '{sched}'; role default is '{role_sched[name]}'",
                }
            )
    return findings


def detect_frontmatter_missing(repo: Path, cfg: dict) -> list[dict]:
    required = cfg["required_keys"]
    findings = []
    for pattern in cfg.get("globs", ["**/*.md", "**/*.mdx"]):
        for p in sorted(repo.glob(pattern)):
            if not p.is_file():
                continue
            fm = read_frontmatter(p)
            if fm is None:
                findings.append({"path": _rel(repo, p), "line": 1, "evidence": "no frontmatter block"})
                continue
            missing = [k for k in required if k not in fm]
            if missing:
                findings.append(
                    {"path": _rel(repo, p), "line": 1, "evidence": f"missing frontmatter key(s): {', '.join(missing)}"}
                )
    return findings


_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def detect_broken_links(repo: Path, cfg: dict) -> list[dict]:
    findings = []
    repo_resolved = repo.resolve()
    for pattern in cfg.get("globs", ["**/*.md", "**/*.mdx"]):
        for p in sorted(repo.glob(pattern)):
            if not p.is_file():
                continue
            for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
                for m in _LINK_RE.finditer(line):
                    target = m.group(1).split("#")[0].strip()
                    if not target or target.startswith(("http://", "https://", "mailto:", "/")):
                        continue
                    resolved = (p.parent / target).resolve()
                    try:
                        resolved.relative_to(repo_resolved)
                    except ValueError:
                        continue  # points outside the repo tree; not ours to judge
                    if not resolved.exists():
                        findings.append(
                            {"path": _rel(repo, p), "line": i, "evidence": f"broken relative link: {target}"}
                        )
    return findings


def detect_placeholder_text(repo: Path, cfg: dict) -> list[dict]:
    tokens = cfg.get("tokens", ["TODO", "FIXME", "PLACEHOLDER", "TBD"])
    pattern = re.compile(r"\b(" + "|".join(re.escape(t) for t in tokens) + r")\b", re.IGNORECASE)
    findings = []
    for glob_pat in cfg.get("globs", ["**/*.md", "**/*.mdx"]):
        for p in sorted(repo.glob(glob_pat)):
            if not p.is_file():
                continue
            for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
                if pattern.search(line):
                    findings.append({"path": _rel(repo, p), "line": i, "evidence": line.strip()[:200]})
    return findings


def detect_stale_fact_token(repo: Path, cfg: dict) -> list[dict]:
    findings = []
    for rule in cfg.get("tokens", []):
        token, doc_glob, code_glob = rule["token"], rule["doc_glob"], rule["code_glob"]
        code_hit = any(
            token in p.read_text(errors="replace") for p in repo.glob(code_glob) if p.is_file()
        )
        if code_hit:
            continue
        for p in sorted(repo.glob(doc_glob)):
            if not p.is_file():
                continue
            for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
                if token in line:
                    findings.append(
                        {"path": _rel(repo, p), "line": i, "evidence": f"doc claims '{token}', not found under {code_glob}"}
                    )
    return findings


_MDLINT_RE = re.compile(r"^(.+?):(\d+)(?::\d+)?\s+(MD\d+.*)$")


def detect_markdownlint(repo: Path, cfg: dict) -> list[dict]:
    binname = cfg.get("binary", "markdownlint-cli2")
    if shutil.which(binname) is None:
        raise SystemExit(f"{binname} not found on PATH; check cannot run")
    globs = cfg.get("globs", ["**/*.md"])
    try:
        out = subprocess.run(
            [binname, *globs, "--no-progress"], cwd=repo, capture_output=True, text=True, timeout=120
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"{binname} failed to run: {exc}") from exc
    findings = []
    for line in (out.stdout + out.stderr).splitlines():
        m = _MDLINT_RE.match(line.strip())
        if m:
            path, lineno, evidence = m.groups()
            findings.append({"path": path, "line": int(lineno), "evidence": evidence})
    return findings


def detect_skill_frontmatter(repo: Path, cfg: dict) -> list[dict]:
    required = cfg.get("required_keys", ["name", "description", "version"])
    findings = []
    for p in sorted(repo.glob(cfg.get("glob", "**/SKILL.md"))):
        fm = read_frontmatter(p)
        missing = [k for k in required if not fm or k not in fm]
        if missing:
            findings.append(
                {"path": _rel(repo, p), "line": 1, "evidence": f"missing frontmatter key(s): {', '.join(missing)}"}
            )
    return findings


_TARGET_RE = re.compile(r'target\s*=\s*"([^"]+)"')


def detect_allowlist_review(repo: Path, cfg: dict) -> list[dict]:
    p = repo / cfg["allowlist_file"]
    if not p.exists():
        return []
    text = p.read_text(errors="replace")
    lines = text.splitlines()
    findings = []
    for i, line in enumerate(lines, 1):
        m = _TARGET_RE.search(line)
        if not m:
            continue
        target = m.group(1)
        skill_name = target.rsplit("/", 1)[-1]
        preceding = "\n".join(lines[: i - 1])
        if skill_name not in preceding:
            findings.append(
                {
                    "path": cfg["allowlist_file"],
                    "line": i,
                    "evidence": f"allowlist entry '{target}' has no review record above it",
                }
            )
    return findings


def detect_contradiction(repo: Path, cfg: dict) -> list[dict]:
    findings = []
    for rule in cfg.get("rules", []):
        pa, pb = repo / rule["file_a"], repo / rule["file_b"]
        if not pa.exists() or not pb.exists():
            continue
        ta, tb = pa.read_text(errors="replace"), pb.read_text(errors="replace")
        if re.search(rule["pattern_a"], ta) and re.search(rule["pattern_b"], tb):
            findings.append(
                {
                    "path": rule["file_a"],
                    "line": 1,
                    "evidence": f"{rule['message']} ({rule['file_a']} vs {rule['file_b']})",
                }
            )
    return findings


def detect_stale_artifacts(repo: Path, cfg: dict) -> list[dict]:
    max_age_days = cfg.get("max_age_days", 30)
    cutoff = time.time() - max_age_days * 86400
    findings = []
    for pattern in cfg.get("globs", ["**/.worktrees/*", "**/*.bak"]):
        for p in sorted(repo.glob(pattern)):
            try:
                mtime = p.stat().st_mtime
            except OSError:
                continue
            if mtime < cutoff:
                age_days = int((time.time() - mtime) / 86400)
                findings.append(
                    {"path": _rel(repo, p), "line": 1, "evidence": f"stale artifact, unmodified for {age_days}d"}
                )
    return findings


DETECTORS = {
    "cron_drift": detect_cron_drift,
    "frontmatter_missing": detect_frontmatter_missing,
    "broken_links": detect_broken_links,
    "placeholder_text": detect_placeholder_text,
    "stale_fact_token": detect_stale_fact_token,
    "markdownlint": detect_markdownlint,
    "skill_frontmatter": detect_skill_frontmatter,
    "allowlist_review": detect_allowlist_review,
    "contradiction": detect_contradiction,
    "stale_artifacts": detect_stale_artifacts,
}


def run(repo: Path, checks: list[dict], only_id: str | None, repo_name: str, out=sys.stdout) -> int:
    emitted = 0
    for check in checks:
        if only_id and check["id"] != only_id:
            continue
        fn = DETECTORS.get(check["detect"])
        if fn is None:
            raise SystemExit(f"unknown detector: {check['detect']!r} (check {check['id']})")
        for f in fn(repo, check.get("config", {})):
            print(
                json.dumps({"check_id": check["id"], "repo": repo_name, **f}),
                file=out,
            )
            emitted += 1
    return emitted


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", required=True, type=Path, help="path to the checked-out target repo")
    ap.add_argument("--repo-name", required=True, help="owner/repo, carried into each finding's 'repo' field")
    ap.add_argument(
        "--checklist", type=Path, default=Path(__file__).resolve().parent.parent / "checklist.json"
    )
    ap.add_argument("--check", help="run only this check id")
    args = ap.parse_args()
    checklist = json.loads(args.checklist.read_text())
    run(args.repo, checklist["checks"], args.check, args.repo_name)


if __name__ == "__main__":
    main()
