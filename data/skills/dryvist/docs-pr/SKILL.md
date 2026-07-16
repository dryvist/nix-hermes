---
name: dryvist-docs-pr
description: Open signed, draft, no-merge doc PRs to dryvist docs repos
version: 1.0.0
author: dryvist homelab
license: MIT
platforms: [linux]
metadata:
  hermes:
    category: research
    tags: [github, documentation, dryvist]
    related_skills: [research/llm-wiki, github/github-pr-workflow]
---

# dryvist docs-pr

Contribute documentation to the two dryvist doc sites by opening **draft,
never-merged** pull requests whose commits are **GitHub-verified** (signed). Use
this after you have curated knowledge in the `llm-wiki` and identified a concrete,
sourced documentation improvement.

Repos:
- `dryvist/docs` (PUBLIC, Mintlify) — user-facing public docs, docs.jacobpevans.com.
- `dryvist/docs-starlight` (PRIVATE, Astro Starlight) — internal docs, docs.dryvist.com.

## Hard rules (never violate)

1. **Draft only. Never merge.** Every PR opens as a draft. You have no authority
   to merge, mark ready, or approve. A human reviews and merges. The org ruleset
   also blocks you — do not try to work around it.
2. **Signed commits via the API only.** Commit exclusively through
   `scripts/open_signed_pr.py` (GitHub App + `createCommitOnBranch`). NEVER
   `git commit`/`git push` — the org requires signed commits and a plain push is
   rejected.
3. **Privacy routing is absolute.** Anything internal, sensitive, or secret
   (hostnames, internal domains, IPs, tokens, private topology) goes to
   `docs-starlight` ONLY — never to the public `docs`. When unsure, treat it as
   sensitive. Redact secrets from every string before it leaves the machine.
4. **No emoji** anywhere in branch names, titles, commit messages, or bodies.
5. **Attribution triad** on every PR: title suffix ` [routine:hermes]`, label
   `cloud-routine`, and a `## Provenance` block in the body naming the source(s).
6. **Caps + de-dup.** Max 1 open PR per repo per day from this skill. Before
   opening, list existing open PRs and skip if a matching `docs:` PR already
   exists. If over the cap or a duplicate, decline cleanly — do nothing.
7. **Small, sourced, voice-preserving.** One focused improvement per PR. Cite
   provenance. Never restyle or rewrite an author's voice.
8. **Fail loud.** If App creds are missing or a preflight check fails, stop and
   report — never fall back to an unsigned or non-draft path.

## Procedure

1. Preflight: `python scripts/open_signed_pr.py --preflight` — confirms the App
   token mints. Abort on failure.
2. Decide the target repo by privacy (rule 3). Confirm the change is worth a PR
   (a real, sourced improvement — otherwise decline).
3. Prepare the file change(s) as full new file contents.
4. De-dup: check open PRs; if a matching `docs:` PR exists or the daily cap is
   hit, stop.
5. Open the PR via the helper — it creates a dated branch
   `docs/hermes/<slug>-<YYYY-MM-DD>`, commits signed via the API, and opens a
   DRAFT PR with the attribution triad. Report the PR URL. Do not touch it again.

## Verification

- The helper's unit tests (`tests/test_open_signed_pr.py`) assert: draft=True,
  dated branch, `docs:` Conventional-Commit title with the `[routine:hermes]`
  suffix, `## Provenance` body block, cap/de-dup logic, secret redaction, and
  privacy routing (sensitive content never targets public `docs`). Run:
  `python -m pytest tests/ -q`.
- A live PR is proof only if `gh api repos/<owner>/<repo>/pulls/<n>` shows
  `draft: true` and the head commit's `verification.verified == true`.
