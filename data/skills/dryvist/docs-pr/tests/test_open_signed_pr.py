"""Unit tests for the dryvist docs-pr signed-PR helper. No network calls."""
import base64
import datetime as dt
import sys
from pathlib import Path
from unittest import mock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import open_signed_pr as m  # noqa: E402


def test_dated_branch_shape():
    b = m.dated_branch("Add Hermes wiki section", today=dt.date(2026, 7, 8))
    assert b == "docs/hermes/add-hermes-wiki-section-2026-07-08"
    assert b.startswith("docs/hermes/") and b.endswith("2026-07-08")


def test_build_title_prefixes_and_suffixes():
    t = m.build_title("document the wiki")
    assert t == "docs: document the wiki [routine:hermes]"
    # does not double-prefix
    assert m.build_title("docs: already").startswith("docs: already")
    assert t.endswith(m.ATTRIBUTION_SUFFIX)


def test_title_and_body_reject_emoji():
    with pytest.raises(m.DocsPRError):
        m.build_title("shipped it \U0001f680")
    with pytest.raises(m.DocsPRError):
        m.build_body("done \U0001f389", [])


def test_body_has_provenance_block():
    body = m.build_body("summary text", ["https://example.com/a"])
    assert "## Provenance" in body
    assert "https://example.com/a" in body


def test_redaction_scrubs_secrets():
    assert "ghp_" not in m.redact("token ghp_" + "a" * 36)
    assert "[REDACTED]" in m.redact("api_key=supersecretvalue")
    pem = "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----"
    assert "PRIVATE KEY" not in m.redact(pem)


def test_privacy_routing_blocks_sensitive_to_public():
    assert m.pick_repo(True, "docs-starlight") == "docs-starlight"
    with pytest.raises(m.DocsPRError):
        m.pick_repo(True, "docs")  # sensitive -> public is forbidden
    assert m.pick_repo(False, "docs") == "docs"


def test_cap_and_dedup():
    assert m.within_cap(0, cap=1) is True
    assert m.within_cap(1, cap=1) is False
    titles = ["docs: document the wiki [routine:hermes]"]
    assert m.is_duplicate(titles, "docs: document the wiki [routine:hermes]") is True
    assert m.is_duplicate(titles, "docs: something else [routine:hermes]") is False


def test_plan_pr_skips_on_cap_and_dup():
    req = m.PRRequest(
        owner="dryvist", requested_repo="docs", summary="x",
        sources=[], changes=[m.FileChange("a.md", "hi")],
        open_pr_count_today=1,
    )
    assert m.plan_pr(req).get("skip")  # cap reached
    req2 = m.PRRequest(
        owner="dryvist", requested_repo="docs", summary="dup",
        sources=[], changes=[m.FileChange("a.md", "hi")],
        open_pr_titles=["docs: dup [routine:hermes]"],
    )
    assert m.plan_pr(req2).get("skip")  # duplicate


def test_plan_pr_happy_path_is_draft_and_encoded():
    req = m.PRRequest(
        owner="dryvist", requested_repo="docs", summary="Add wiki docs",
        sources=["wiki/entities/hermes.md"],
        changes=[m.FileChange("infrastructure/hermes-agent.mdx", "body")],
    )
    plan = m.plan_pr(req)
    assert plan["draft"] is True
    assert plan["repo"] == "docs"
    assert plan["branch"].startswith("docs/hermes/add-wiki-docs-")
    assert plan["title"] == "docs: Add wiki docs [routine:hermes]"
    add = plan["additions"][0]
    assert base64.b64decode(add["contents"]).decode() == "body"


def test_plan_pr_requires_changes():
    with pytest.raises(m.DocsPRError):
        m.plan_pr(m.PRRequest("dryvist", "docs", "x", [], []))


def test_open_pr_via_api_uses_draft_and_signed_commit():
    gh = mock.MagicMock()
    gh.rest.repos.get.return_value.parsed_data.default_branch = "main"
    gh.rest.git.get_ref.return_value.parsed_data.object_.sha = "baseoid123"
    gh.rest.pulls.create.return_value.parsed_data.html_url = "https://github.com/dryvist/docs/pull/9"
    gh.rest.pulls.create.return_value.parsed_data.number = 9
    plan = {
        "owner": "dryvist", "repo": "docs", "branch": "docs/hermes/x-2026-07-08",
        "title": "docs: x [routine:hermes]", "body": "b",
        "additions": [{"path": "a.md", "contents": "aGk="}], "label": "cloud-routine",
        "draft": True,
    }
    url = m.open_pr_via_api(gh, plan)
    assert url == "https://github.com/dryvist/docs/pull/9"
    # branch created from base oid, PR opened as draft, commit via graphql (signed)
    gh.rest.git.create_ref.assert_called_once()
    assert gh.graphql.call_count == 1
    _, kwargs = gh.rest.pulls.create.call_args
    assert kwargs["draft"] is True
    gq_args = gh.graphql.call_args[0]
    assert gq_args[1]["input"]["expectedHeadOid"] == "baseoid123"


def test_make_client_fails_loud_without_creds(monkeypatch):
    for v in ("GITHUB_APP_ID", "GITHUB_APP_INSTALLATION_ID", "GITHUB_APP_PRIVATE_KEY_PATH"):
        monkeypatch.delenv(v, raising=False)
    with pytest.raises(m.DocsPRError):
        m.make_client()
