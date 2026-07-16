---
name: dryvist-github-issues
description: Triage, create and update GitHub Issues (all repos) and manage dryvist org Projects v2
version: 1.0.0
author: dryvist homelab
license: MIT
platforms: [linux]
metadata:
  hermes:
    category: research
    tags: [github, issues, projects, dryvist]
    related_skills: [dryvist/docs-pr, github/github-pr-workflow]
---

# dryvist github-issues

Manage GitHub **Issues** and **Projects (v2)** using the fine-grained PAT
`GH_PAT_WRITE_PROJECT_ISSUES`, delivered into this agent's environment (`.env`).

## Purpose

`GH_PAT_WRITE_PROJECT_ISSUES` grants:

- **read + write GitHub Issues across ALL repos** — read, search, create,
  comment on, update, label and close issues, and
- **read + write Projects (v2) in the `dryvist` org** — read boards and add /
  move items on them,

plus a few incidental read scopes. Use it for issue triage and org project-board
management.

**It is NOT for:**

- **code commits** — signed commits go through the separate `dryvist/docs-pr`
  skill (GitHub App + `createCommitOnBranch`). This token cannot and must not
  push code.
- **merging** — you have no authority to merge, mark ready, or approve anything.

Respect least privilege: this token is scoped to issues + projects only. Do not
attempt to use it for pushes, PR merges, or any admin action.

## How to use

Call the GitHub **REST API** for issues and the **GraphQL API** for Projects v2,
authenticating with `Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES`. Read
the token from the environment at use time — never hardcode it.

### Issues (REST)

Get one issue:

```bash
curl -sS -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/{owner}/{repo}/issues/{n}
```

List issues (include closed):

```bash
curl -sS -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/{owner}/{repo}/issues?state=all&per_page=50"
```

Search issues across repos:

```bash
curl -sS -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/search/issues?q=repo:dryvist/ansible-proxmox-apps+is:issue+is:open+label:bug"
```

Create an issue:

```bash
curl -sS -X POST -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/{owner}/{repo}/issues \
  -d '{"title":"fix: honeypot index missing","body":"Details and repro.","labels":["bug"]}'
```

Comment on an issue:

```bash
curl -sS -X POST -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/{owner}/{repo}/issues/{n}/comments \
  -d '{"body":"Confirmed on the latest converge."}'
```

Update / relabel an issue:

```bash
curl -sS -X PATCH -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/{owner}/{repo}/issues/{n} \
  -d '{"labels":["bug","triage"]}'
```

Close an issue:

```bash
curl -sS -X PATCH -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/{owner}/{repo}/issues/{n} \
  -d '{"state":"closed"}'
```

### Projects v2 (GraphQL)

All Projects v2 calls go to `https://api.github.com/graphql`.

List the dryvist org's projects (get each project's `number`, `title`, `id`):

```bash
curl -sS -X POST -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  https://api.github.com/graphql \
  -d '{"query":"query { organization(login: \"dryvist\") { projectsV2(first: 20) { nodes { number title id } } } }"}'
```

Add an issue to a project. First fetch the issue's node id, then add it:

```bash
# 1) issue node id
curl -sS -X POST -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  https://api.github.com/graphql \
  -d '{"query":"query { repository(owner: \"dryvist\", name: \"ansible-proxmox-apps\") { issue(number: 123) { id } } }"}'

# 2) add it (projectId from the list query above, contentId = issue node id)
curl -sS -X POST -H "Authorization: Bearer $GH_PAT_WRITE_PROJECT_ISSUES" \
  https://api.github.com/graphql \
  -d '{"query":"mutation { addProjectV2ItemById(input: {projectId: \"PVT_xxx\", contentId: \"I_xxx\"}) { item { id } } }"}'
```

## Guardrails

1. **Read before you write.** Fetch the repo/issue (and existing comments) before
   editing, commenting, or closing — never act on a stale assumption.
2. **Clear, conventional titles.** Use a `type: summary` style (`fix:`, `feat:`,
   `docs:`, `chore:`) and a concise, specific summary.
3. **Don't spam.** One focused issue or comment per concern; de-dup against open
   issues first; do not reopen churn.
4. **Label appropriately** so triage and project automation can route the item.
5. **Never leak the token.** Never paste `GH_PAT_WRITE_PROJECT_ISSUES` (or any
   secret) into an issue body, comment, PR text, or log output.
6. **Issues + projects only.** This token is least-privilege by design — do not
   use it (or attempt to use it) for code pushes, PR merges, or admin actions.
   Code changes are the `dryvist/docs-pr` signed-commit path; merges are human-only.
