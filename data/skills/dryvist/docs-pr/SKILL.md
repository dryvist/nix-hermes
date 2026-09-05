---
name: dryvist-docs-pr
description: Open signed, draft, no-merge doc PRs to the private dryvist docs site
version: 1.1.0
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

Contribute documentation to the private dryvist doc site by opening **draft,
never-merged** pull requests whose commits are **GitHub-verified** (signed). Use
this after you have curated knowledge in the `llm-wiki` and identified a concrete,
sourced documentation improvement.

Repo: `dryvist/docs-starlight` (PRIVATE, Astro Starlight) — internal docs.

Publishing to the public docs site is not this skill's job: the publish workflow
in `docs-starlight` projects the pages marked publishable and owns that path end
to end.

## Hard rules (never violate)

1. **Draft only. Never merge.** Every PR opens as a draft. You have no authority
   to merge, mark ready, or approve. A human reviews and merges. The org ruleset
   also blocks you — do not try to work around it.
2. **Signed commits via the API only.** Commit exclusively through the
   `createCommitOnBranch` GraphQL mutation, which signs server-side under the
   App identity. NEVER `git commit`/`git push` — the org requires signed commits
   and a plain push is rejected.
3. **Private site only.** Everything you author here targets `docs-starlight`.
   Never open a PR against the public docs repo, and redact secrets from every
   string before it leaves the machine.
4. **No emoji** anywhere in branch names, titles, commit messages, or bodies.
5. **Attribution triad** on every PR: title suffix ` [routine:hermes]`, label
   `cloud-routine`, and a `## Provenance` block in the body naming the source(s).
6. **Caps + de-dup.** Max 1 open PR per repo per day from this skill. Before
   opening, list existing open PRs and skip if a matching `docs:` PR already
   exists. If over the cap or a duplicate, decline cleanly — do nothing.
7. **Small, sourced, voice-preserving.** One focused improvement per PR. Cite
   provenance. Never restyle or rewrite an author's voice.
8. **Fail loud.** If the token is missing or a preflight check fails, stop and
   report — never fall back to an unsigned or non-draft path.

## Credential

`GH_TOKEN` is an App installation token, already in your environment. You do not
mint it and you do not print it. If `gh auth status` reports no token, stop
(rule 8).

## Procedure

Set `R=dryvist/docs-starlight`, `B=docs/hermes/<slug>-$(date +%F)`.

1. Preflight. Both must succeed before you touch anything:

   ```sh
   BASE=$(gh api "repos/$R" --jq .default_branch)
   gh pr list -R "$R" --author @me --state open --json number,title
   ```

   The second is also your rule 6 check: stop if a matching `docs:` PR is open
   or you already opened one today.

2. Branch off the default branch's tip:

   ```sh
   OID=$(gh api "repos/$R/git/ref/heads/$BASE" --jq .object.sha)
   gh api "repos/$R/git/refs" -f ref="refs/heads/$B" -f sha="$OID"
   ```

3. Commit signed. `createCommitOnBranch` signs server-side, so there is no key
   to hold. `contents` is base64 of the **full new file body**, and
   `expectedHeadOid` is what makes a racing write fail instead of clobber.
   Every variable is a scalar — `gh api graphql` cannot pass a nested input
   object, so the input is built inside the query, not handed in as one:

   ```sh
   gh api graphql \
     -f repo="$R" -f branch="$B" -f oid="$OID" \
     -f path="$PATH_IN_REPO" -f b64="$(base64 -w0 "$LOCAL_FILE")" \
     -f msg="docs: <summary> [routine:hermes]" \
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

   That shape carries one file. For several, add a `$b64N`/`$pathN` pair per
   file and a matching entry in `additions` — one commit per PR, so they all go
   in a single mutation. `deletions: [{path: $path}]` removes a file.

4. Open the draft PR and apply the label:

   ```sh
   gh pr create -R "$R" --draft --base "$BASE" --head "$B" \
     --title "docs: <summary> [routine:hermes]" --body-file body.md \
     --label cloud-routine
   ```

   `body.md` carries the `## Provenance` block (rule 5). Report the PR URL and
   do not touch it again.

## Verification

A PR is proof only if `gh api repos/dryvist/docs-starlight/pulls/<n>` shows
`draft: true` and the head commit's `verification.verified == true`:

```sh
gh pr view <n> -R "$R" --json isDraft,headRefOid
gh api "repos/$R/commits/<oid>" --jq .commit.verification.verified
```

Both must be true. If `verified` is false the commit did not go through the
mutation — the PR is invalid, say so and stop.
