---
name: dryvist-github-issues
description: Read, triage, create and update GitHub Issues across dryvist repos through the minted gh wrapper
version: 1.1.0
author: dryvist homelab
license: MIT
platforms: [linux]
metadata:
  hermes:
    category: research
    tags: [github, issues, dryvist]
    related_skills: [dryvist/docs-pr, github/github-pr-workflow]
---

# dryvist github-issues

Read and update GitHub **Issues** with the `gh` on `PATH`. That `gh` is the
Hermes wrapper: it picks a short-lived installation token per call, enforces
the public/private repository boundary, and gates writes to public repositories.
Do not call GitHub with `curl`, and do not pass an authorization header.

## Choosing the token set

Every call sets two variables:

- `HERMES_TRUST_BOUNDARY=public` or `private`: the visibility of the target
  repository. The wrapper refuses a repository on the other side, and it
  refuses a call with no readable target when it would write.
- `HERMES_GH_TOKEN_SET`:
  - `review` (the default when unset): read-only. Use it for every read.
  - `author`: write. Set it on every mutation (create, comment, label, update,
    close) and on nothing else.

Read-only work (triage reports, analysis, maintenance review) uses `review` for
every call. Never switch to `author` to get around a refusal. A refusal names
its gate; report it and stop.

## Issues

Read one issue:

```bash
HERMES_TRUST_BOUNDARY=private gh api "repos/$OWNER/$REPO/issues/$NUMBER"
```

List open issues (newest first):

```bash
HERMES_TRUST_BOUNDARY=public gh api "repos/$OWNER/$REPO/issues?state=open&per_page=50"
```

Search issues across dryvist repositories:

```bash
HERMES_TRUST_BOUNDARY=private gh api -X GET search/issues \
  -f q="org:dryvist is:issue is:open label:bug"
```

Create an issue:

```bash
HERMES_TRUST_BOUNDARY=public HERMES_GH_TOKEN_SET=author gh api "repos/$OWNER/$REPO/issues" \
  --method POST --input - <<'JSON'
{"title":"fix: a concise title","body":"Evidence and next steps.","labels":["bug"]}
JSON
```

Comment on an issue:

```bash
HERMES_TRUST_BOUNDARY=private HERMES_GH_TOKEN_SET=author gh api "repos/$OWNER/$REPO/issues/$NUMBER/comments" \
  --method POST --input - <<'JSON'
{"body":"Confirmed on the latest converge."}
JSON
```

Relabel, or close an issue:

```bash
HERMES_TRUST_BOUNDARY=public HERMES_GH_TOKEN_SET=author gh api "repos/$OWNER/$REPO/issues/$NUMBER" \
  --method PATCH --input - <<'JSON'
{"labels":["bug","triage"]}
JSON
```

```bash
HERMES_TRUST_BOUNDARY=public HERMES_GH_TOKEN_SET=author gh api "repos/$OWNER/$REPO/issues/$NUMBER" \
  --method PATCH --input - <<'JSON'
{"state":"closed"}
JSON
```

## Projects v2

This skill does not change organization Projects v2 boards. The wrapper needs a
repository target for a write, and a board move has none, so the call is
refused. Report the board action that is needed and stop; do not try to work
around the refusal.

## Guardrails

1. **Read before you write.** Fetch the issue and its existing comments before
   you edit, comment on, or close it.
2. **Clear, conventional titles.** Use a `type: summary` style (`fix:`, `feat:`,
   `docs:`, `chore:`) and a concise, specific summary.
3. **Don't spam.** One focused issue or comment per concern. De-duplicate
   against open issues first, and do not reopen churn.
4. **Label appropriately** so triage and project automation can route the item.
5. **Never leak credentials.** Never paste a token, a token file path, or a
   secret into an issue body, comment, PR text, or log output.
6. **Issues only.** Code changes go through the `dryvist/docs-pr` signed-commit
   path. Merges, approvals, and admin actions are human-only.
