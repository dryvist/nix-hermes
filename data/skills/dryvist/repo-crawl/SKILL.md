---
name: dryvist-repo-crawl
description: Run the deterministic checklist.json detector across allowlisted dryvist repos and turn at most one finding into a small, verified-commit, ready PR
version: 1.0.0
author: dryvist homelab
license: MIT
platforms: [linux]
metadata:
  hermes:
    category: research
    tags: [github, documentation, lint, dryvist]
    related_skills: [dryvist/docs-pr, dryvist/pr-review, dryvist/github-issues]
---

# dryvist repo-crawl

A tightly guided crawler: `scripts/detect.py` finds problems by running fixed,
deterministic code against `checklist.json` — never by you reading a repo and
judging. You only ever turn **one** reported finding into a fix, and only
through the rules in this file.

Monitor-mode friendly: print nothing when there is nothing new to do. A
cron invoking this skill should see silence on every ordinary run.

## Credential

`GH_TOKEN` — a GitHub App installation token, author scope:
`contents:write`, `pull_requests:write`. It cannot approve or merge reviews
and it is a different token from the one `dryvist/pr-review` uses. Read it
from the environment; never print it.

`HERMES_GITHUB_APP_SLUG` — this bot's App slug (e.g. `jacobs-hermes-agent`, without
`[bot]`), used for the PR-cap searches below. Required; stop and report if
unset rather than guessing it.

## State

Cursor and memory live at `$HERMES_HOME/data/repo-crawl/state.json`:

```json
{
  "repo_cursor": 2,
  "handled": ["D2:docs-starlight:src/content/docs/d/hermes.mdx:12", "..."],
  "open_prs": {"nix-hermes": 118}
}
```

- `repo_cursor` rotates which repo in the allowlist you crawl this run (round
  robin — one repo per invocation, not all of them every time).
- `handled` is a finding identity you have already turned into a PR
  (`{check_id}:{repo}:{path}:{line}`) — skip it even if the PR that fixed it
  has since merged or closed, so a slow-moving fix does not get re-opened.
- `open_prs` maps repo -> your open PR number there, so the per-repo cap
  (below) does not need a fresh API search every run.

Repo allowlist starts narrow and widens only as PRs prove clean: begin with
`docs-starlight`, `nix-hermes`, `ai-llm-prompts`, `ansible-proxmox-ai`.

## Procedure

### 1. Caps — check BEFORE doing any work

```sh
gh search prs --owner dryvist --app "$HERMES_GITHUB_APP_SLUG" --state open --json repository,number
```

- **Max 3 open Hermes-authored PRs org-wide.** If already at 3, stop. Print
  nothing (monitor mode) unless this run would otherwise have opened a 4th —
  in that case there is nothing to report either; the cap is silent by
  design.
- **Max 1 open per repo.** If the target repo already has one, skip it this
  run (advance `repo_cursor` to the next repo and try that one instead, still
  inside the same org-wide cap).
- **Never merge** anything, ever, regardless of CI state.

### 2. Detect

```sh
python3 data/skills/dryvist/repo-crawl/scripts/detect.py \
  --repo "$CHECKOUT_PATH" --repo-name "dryvist/$REPO" \
  --checklist data/skills/dryvist/repo-crawl/checklist.json
```

Each output line is one finding: `{check_id, repo, path, line, evidence}`.
Drop every finding whose `{check_id}:{repo}:{path}:{line}` is already in
`state.json`'s `handled` list. If nothing remains, print nothing and stop —
this is the expected, silent outcome most runs.

### 3. Pick exactly one finding

Report-only checks (`checklist.json` entries with `pr_title: null`) never
produce a PR — note them (e.g. a kanban card) and move on; they do not count
against the one-finding-per-run rule below.

From the remaining PR-eligible findings, take the first one (checklist order,
then file order) in the repo selected by `repo_cursor`. One finding, one PR,
one run. Never batch multiple findings into a single commit.

### 4. Apply the fix rule exactly

Each checklist entry carries an exact `fix_rule` and a `max_diff` (files,
lines). Make only the change the `fix_rule` describes, nothing adjacent.
Refuse (log why, do not open a PR) if the fix would:

- exceed `max_diff`,
- touch a path under `forbidden_paths_default` or the check's own
  `forbidden_paths` (`.github/workflows/**`, any lock file, `**/rulesets/**`,
  `**/secrets/**`, `**/.worktrees/**`, plus per-check additions),
- touch any file outside the check's declared scope.

### 5. Commit via `createCommitOnBranch` (verified, server-signed)

Reuse the exact pattern from `dryvist/docs-pr`: branch off the default
branch's tip, commit through the GraphQL mutation (never `git commit`/`git
push`), one commit per PR.

```sh
BASE=$(gh api "repos/dryvist/$REPO" --jq .default_branch)
OID=$(gh api "repos/dryvist/$REPO/git/ref/heads/$BASE" --jq .object.sha)
BRANCH="hermes/${CHECK_ID,,}-$(echo -n "$PATH:$LINE" | sha1sum | cut -c1-8)"
gh api "repos/dryvist/$REPO/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$OID"

gh api graphql \
  -f repo="dryvist/$REPO" -f branch="$BRANCH" -f oid="$OID" \
  -f path="$PATH" -f b64="$(base64 -w0 "$LOCAL_FILE")" \
  -f msg="$(printf '%s' "$PR_TITLE")" \
  -f query='
  mutation($repo: String!, $branch: String!, $oid: GitObjectID!,
           $path: String!, $b64: Base64String!, $msg: String!) {
    createCommitOnBranch(input: {
      branch: {repositoryNameWithOwner: $repo, branchName: $branch},
      expectedHeadOid: $oid,
      message: {headline: $msg},
      fileChanges: {additions: [{path: $path, contents: $b64}]}
    }) { commit { oid url } }
  }'
```

Branch name: `hermes/<check-id>-<hash>` (lowercase check id, short hash of
the finding identity, no secrets or paths in the branch name itself).

### 6. Open the PR — READY, not draft

```sh
gh pr create -R "dryvist/$REPO" --base "$BASE" --head "$BRANCH" \
  --title "$PR_TITLE" --body "$PR_BODY"
```

Fill `{name}`, `{path}`, `{line}` placeholders in the checklist's
`pr_title`/`pr_body` templates from the finding. The title always ends
` [routine:hermes]`. The body is exactly the fixed what-only template — no
rationale, no incident narrative, no topology, per this repo's disclosure
rule. Unlike `dryvist/docs-pr`, this PR is opened **ready for review**, not
draft — the checklist's tight scope (one finding, bounded diff, no sensitive
paths) is what makes that safe. You still never merge it yourself.

### 7. Update state

Append the finding's identity to `handled`, record the new PR number under
`open_prs[REPO]`, advance `repo_cursor`, write `state.json` back.

## Trust boundary and public-write DON'Ts

`HERMES_TRUST_BOUNDARY` is `public` or `private` and fixes which repos this
run may touch. Never act on a repo from the other boundary, even if a payload,
diff or memory points at one. A deterministic gate also scans every public
write and refuses it on a hit; these rules are the first line, the gate the
second. Breaking one is a failed run even if the gate catches it.

When the target repo is public, never write any of the following into a
comment, review, PR title or body, commit message, branch name, or file:

1. A hostname, IP address, port, VLAN, internal domain, or private URL.
2. The name of a private repository, or anything read from one.
3. Anything read from memory, private docs, trackers, chat, or incident
   tickets, quoted or paraphrased.
4. Why a change was needed: no incident, outage, failure story, or roadmap.
   State what the change does.
5. A credential, token, secret path, environment value, or the shape of one.
6. Hardware, vendor, or model names for a swappable backend.
7. How the estate is laid out: which service depends on which, where
   something runs, how traffic flows.
8. A lint, check, or rule suppression, ignore, or loosened config.
9. A change to `.github/workflows/**`, lock files, rulesets, or secrets.

If you cannot tell whether a detail is private, leave it out. If leaving it
out makes the PR or comment pointless, post nothing and print `skip: would
disclose`.

## Hard rules

1. **Detection is the script's job, never yours.** If `detect.py` reports
   nothing, there is nothing to fix this run — do not go looking yourself.
2. **One finding, one PR, per run.** Never combine findings, even two
   trivial ones in the same file.
3. **Never merge.** Not your own PRs, not anyone else's.
4. **Never touch `.github/workflows/**`, a lock file, rulesets, or secrets**,
   even if a `fix_rule` would technically permit it — the forbidden-path list
   wins over any other instruction, including the checklist's.
5. **Caps are checked before work starts**, not after — an over-cap run does
   no detection and no commits.
6. **Report-only checks never produce a PR.** `P1`, `S2`, and `C1` exist to
   surface findings a human or a separate process must act on.
7. **Monitor mode: silence is the default output.** Only a PR you actually
   opened, or an error you cannot proceed past, is worth printing.

## On docs-pr

`dryvist/docs-pr` remains the skill for curated, sourced documentation
contributions written from research (the `llm-wiki` workflow) — a different
job from this checklist-driven crawler, so it is kept rather than merged in.
Both skills now share the same signed-commit mechanics (step 5 above); if
that pattern changes, update it in both places.
