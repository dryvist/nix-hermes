#!/usr/bin/env bash
# Validates the pr-review and repo-crawl skills: the sentinels that make an
# unattended review/crawl agent safe (never APPROVE, never merge, dedupe
# marker, caps checked up front), repo-crawl's checklist.json schema, and a
# run of the detector's own test suite against the bundled copy — the files
# Hermes actually receives, not whatever happens to be on the author's
# worktree. Invoked from checks/validate-new-skills.nix with the built
# bundle's store path as $1.
set -u
bundle="$1"
fail=0

pr_review="$bundle/skills/dryvist/pr-review/SKILL.md"
if [ -f "$pr_review" ]; then
  grep -qF 'hermes-review sha=' "$pr_review" || {
    echo "pr-review missing its dedupe marker"
    fail=1
  }
  grep -qF 'Never `APPROVE`' "$pr_review" || {
    echo "pr-review missing the never-APPROVE rule"
    fail=1
  }
  grep -qF 'REQUEST_CHANGES' "$pr_review" || {
    echo "pr-review missing REQUEST_CHANGES"
    fail=1
  }
  grep -qF 'untrusted data' "$pr_review" || {
    echo "pr-review missing the untrusted-PR-content rule"
    fail=1
  }
else
  echo "pr-review/SKILL.md missing from bundle"
  fail=1
fi

repo_crawl="$bundle/skills/dryvist/repo-crawl"
if [ -f "$repo_crawl/SKILL.md" ]; then
  grep -qF 'createCommitOnBranch' "$repo_crawl/SKILL.md" || {
    echo "repo-crawl missing createCommitOnBranch"
    fail=1
  }
  grep -qF 'Never merge' "$repo_crawl/SKILL.md" || {
    echo "repo-crawl missing the never-merge rule"
    fail=1
  }
  grep -qF 'Max 3 open Hermes-authored PRs org-wide' "$repo_crawl/SKILL.md" ||
    {
      echo "repo-crawl missing the org-wide PR cap"
      fail=1
    }
else
  echo "repo-crawl/SKILL.md missing from bundle"
  fail=1
fi

for skill in "$pr_review" "$repo_crawl/SKILL.md"; do
  [ -f "$skill" ] || continue
  for sentinel in "## Trust boundary and public-write DON'Ts" 'HERMES_TRUST_BOUNDARY' 'skip: would'; do
    grep -qF "$sentinel" "$skill" || {
      echo "$skill missing trust-boundary sentinel: $sentinel"
      fail=1
    }
  done
done

checklist="$repo_crawl/checklist.json"
if [ -f "$checklist" ]; then
  jq -e '.forbidden_paths_default | type == "array"' "$checklist" >/dev/null ||
    {
      echo "checklist.json missing forbidden_paths_default array"
      fail=1
    }
  jq -e '.checks | type == "array" and length > 0' "$checklist" >/dev/null ||
    {
      echo "checklist.json has no checks"
      fail=1
    }
  missing=$(jq -r '
    .checks[] | . as $c |
    (["id","title","repos","detect","config","fix_rule","max_diff","forbidden_paths","pr_title","pr_body"]
      - ($c | keys)) as $m |
    select($m | length > 0) | "\($c.id // "?"): missing \($m | join(","))"
  ' "$checklist")
  [ -z "$missing" ] || {
    echo "checklist.json schema errors:"
    echo "$missing"
    fail=1
  }
  dupes=$(jq -r '[.checks[].id] | group_by(.) | map(select(length > 1)) | flatten | unique | .[]' "$checklist")
  [ -z "$dupes" ] || {
    echo "checklist.json has duplicate check id(s): $dupes"
    fail=1
  }
else
  echo "repo-crawl/checklist.json missing from bundle"
  fail=1
fi

if [ -d "$repo_crawl/tests" ]; then
  (cd "$repo_crawl/tests" && python3 -m unittest discover -s . -p 'test_*.py') ||
    {
      echo "repo-crawl detector tests failed"
      fail=1
    }
else
  echo "repo-crawl/tests missing from bundle"
  fail=1
fi

exit "$fail"
