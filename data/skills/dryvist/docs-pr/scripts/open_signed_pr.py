#!/usr/bin/env python3
"""Open a signed, draft, no-merge documentation PR to a dryvist docs repo.

Commits are authored by the `hermes-docs-bot` GitHub App via the
`createCommitOnBranch` GraphQL mutation, so GitHub marks them Verified/signed —
satisfying the org's non-bypassable required-signatures ruleset. A plain
`git push` would be rejected, so this is the ONLY sanctioned write path.

The pure guardrail helpers (naming, title/body, redaction, privacy routing,
cap/de-dup) contain no network calls and are unit-tested. Network access is
isolated behind functions that take a githubkit client, so tests inject a mock.
"""
from __future__ import annotations

import base64
import datetime as _dt
import os
import re
import sys
from dataclasses import dataclass, field

ATTRIBUTION_SUFFIX = " [routine:hermes]"
PROVENANCE_LABEL = "cloud-routine"
PUBLIC_REPO = "docs"
PRIVATE_REPO = "docs-starlight"
DAILY_CAP = 1

_EMOJI = re.compile(
    # \U0001f1e6-\U0001f1ff (regional indicators) is already inside the
    # \U0001f000-\U0001faff block, so it is intentionally not repeated \u2014
    # a nested range trips CodeQL py/overly-large-range (overlapping ranges).
    "[\U0001f000-\U0001faff\U00002600-\U000027bf"
    "\u2190-\u21ff\u2300-\u23ff]"  # + arrows + miscellaneous-technical
)
# Obvious secret shapes to scrub from anything leaving the machine.
_SECRET_PATTERNS = [
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.S),
    re.compile(r"(?i)bearer\s+[A-Za-z0-9._\-]{16,}"),
    re.compile(r"(?i)(api[_-]?key|token|secret|password)\s*[:=]\s*\S+"),
]


class DocsPRError(RuntimeError):
    """Fatal, fail-loud error — never swallow into an unsigned/non-draft path."""


# --------------------------------------------------------------------------- #
# Pure guardrail helpers (unit-tested; no network)                            #
# --------------------------------------------------------------------------- #
def has_emoji(text: str) -> bool:
    return bool(_EMOJI.search(text or ""))


def slugify(summary: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", (summary or "").lower()).strip("-")
    return (s or "update")[:48]


def dated_branch(summary: str, today: _dt.date | None = None) -> str:
    day = (today or _dt.date.today()).isoformat()
    return f"docs/hermes/{slugify(summary)}-{day}"


def build_title(summary: str) -> str:
    summary = (summary or "").strip()
    if has_emoji(summary):
        raise DocsPRError("emoji not allowed in PR title")
    body = summary if summary.lower().startswith("docs:") else f"docs: {summary}"
    return body + ATTRIBUTION_SUFFIX


def build_body(summary: str, sources: list[str]) -> str:
    if has_emoji(summary):
        raise DocsPRError("emoji not allowed in PR body")
    src = "\n".join(f"- {redact(s)}" for s in (sources or [])) or "- (none recorded)"
    return (
        f"{redact(summary).strip()}\n\n"
        "## Provenance\n\n"
        "Opened autonomously by the Hermes agent's `dryvist-docs-pr` skill. "
        "Draft only; a human reviews and merges.\n\n"
        f"Sources:\n{src}\n"
    )


def redact(text: str) -> str:
    out = text or ""
    for pat in _SECRET_PATTERNS:
        out = pat.sub("[REDACTED]", out)
    return out


def pick_repo(sensitive: bool, requested: str) -> str:
    """Enforce privacy routing: sensitive content is docs-starlight ONLY."""
    if sensitive:
        if requested == PUBLIC_REPO:
            raise DocsPRError("sensitive content must not target the public docs repo")
        return PRIVATE_REPO
    if requested not in (PUBLIC_REPO, PRIVATE_REPO):
        raise DocsPRError(f"unknown target repo: {requested!r}")
    return requested


def is_duplicate(open_pr_titles: list[str], title: str) -> bool:
    key = title.split(ATTRIBUTION_SUFFIX)[0].strip().lower()
    return any(key and key in (t or "").lower() for t in open_pr_titles)


def within_cap(open_pr_count_today: int, cap: int = DAILY_CAP) -> bool:
    return open_pr_count_today < cap


@dataclass
class FileChange:
    path: str
    contents: str

    def as_addition(self) -> dict:
        data = base64.b64encode(self.contents.encode()).decode()
        return {"path": self.path, "contents": data}


@dataclass
class PRRequest:
    owner: str
    requested_repo: str
    summary: str
    sources: list[str]
    changes: list[FileChange]
    sensitive: bool = False
    open_pr_titles: list[str] = field(default_factory=list)
    open_pr_count_today: int = 0


def plan_pr(req: PRRequest) -> dict:
    """Pure planning step: resolve repo/branch/title/body, enforce all guardrails.

    Returns a dict describing the PR to open, or raises DocsPRError. Raises a
    *skip* sentinel (returns {'skip': reason}) for cap/dup — a clean no-op.
    """
    repo = pick_repo(req.sensitive, req.requested_repo)
    if not req.changes:
        raise DocsPRError("no file changes to commit")
    title = build_title(req.summary)
    if not within_cap(req.open_pr_count_today):
        return {"skip": "daily cap reached"}
    if is_duplicate(req.open_pr_titles, title):
        return {"skip": "duplicate PR already open"}
    return {
        "owner": req.owner,
        "repo": repo,
        "branch": dated_branch(req.summary),
        "title": title,
        "body": build_body(req.summary, req.sources),
        "additions": [c.as_addition() for c in req.changes],
        "label": PROVENANCE_LABEL,
        "draft": True,
    }


# --------------------------------------------------------------------------- #
# Network layer (thin; a mock client is injected in tests)                    #
# --------------------------------------------------------------------------- #
_COMMIT_MUTATION = """
mutation($input: CreateCommitOnBranchInput!) {
  createCommitOnBranch(input: $input) { commit { url oid } }
}
"""


def make_client():
    app_id = os.environ.get("GITHUB_APP_ID", "")
    inst_id = os.environ.get("GITHUB_APP_INSTALLATION_ID", "")
    key_path = os.environ.get("GITHUB_APP_PRIVATE_KEY_PATH", "")
    if not (app_id and inst_id and key_path and os.path.exists(key_path)):
        raise DocsPRError(
            "missing GitHub App creds (GITHUB_APP_ID / _INSTALLATION_ID / _PRIVATE_KEY_PATH)"
        )
    from githubkit import AppInstallationAuthStrategy, GitHub  # lazy import

    private_key = open(key_path).read()
    return GitHub(AppInstallationAuthStrategy(int(app_id), private_key, int(inst_id)))


def _head_oid(gh, owner: str, repo: str, branch: str) -> str:
    return gh.rest.git.get_ref(owner, repo, f"heads/{branch}").parsed_data.object_.sha


def _default_branch(gh, owner: str, repo: str) -> str:
    return gh.rest.repos.get(owner, repo).parsed_data.default_branch


def open_pr_via_api(gh, plan: dict) -> str:
    """Create the dated branch, commit signed via GraphQL, open a DRAFT PR."""
    owner, repo, branch = plan["owner"], plan["repo"], plan["branch"]
    base = _default_branch(gh, owner, repo)
    base_oid = _head_oid(gh, owner, repo, base)
    gh.rest.git.create_ref(owner, repo, ref=f"refs/heads/{branch}", sha=base_oid)
    gh.graphql(
        _COMMIT_MUTATION,
        {
            "input": {
                "branch": {
                    "repositoryNameWithOwner": f"{owner}/{repo}",
                    "branchName": branch,
                },
                "message": {"headline": plan["title"]},
                "fileChanges": {"additions": plan["additions"], "deletions": []},
                "expectedHeadOid": base_oid,
            }
        },
    )
    pr = gh.rest.pulls.create(
        owner, repo, title=plan["title"], head=branch, base=base,
        body=plan["body"], draft=True,
    ).parsed_data
    try:
        gh.rest.issues.add_labels(owner, repo, pr.number, labels=[plan["label"]])
    except Exception:  # label is best-effort; never block the PR on it
        pass
    return pr.html_url


def preflight() -> None:
    gh = make_client()
    login = gh.rest.apps.get_authenticated().parsed_data.slug
    print(f"preflight OK: app={login}")


def main(argv: list[str]) -> int:
    if "--preflight" in argv:
        preflight()
        return 0
    print("import this module and call plan_pr()/open_pr_via_api(); --preflight to check creds")
    return 0


if __name__ == "__main__":  # pragma: no cover
    try:
        sys.exit(main(sys.argv[1:]))
    except DocsPRError as exc:
        print(f"FATAL: {exc}", file=sys.stderr)
        sys.exit(2)
