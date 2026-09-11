---
name: dryvist-zammad-incidents
description: Open, update, dedupe, triage, resolve, and auto-close typed homelab incidents in Zammad (the ITSM system of record) via its REST API — the durable ticket + knowledge-base layer behind the splunk-monitor alerts, keyed on a stable finding_key, typed as outage/weakness/hygiene with a per-type closure condition, and lifecycle-tagged so agent-managed tickets yield to any human touch
version: 1.2.0
author: dryvist homelab
license: MIT
platforms: [linux]
metadata:
  hermes:
    category: research
    tags: [zammad, itsm, incident, ticketing, dryvist]
    related_skills: [dryvist/splunk-monitor, dryvist/github-issues]
---

# dryvist zammad-incidents

Zammad is the homelab's **incident-management system of record**. When you
confirm something is genuinely wrong, the durable record lives here as a
**ticket** with a threaded narrative; when you resolve it, the runbook/RCA lives
here as a **knowledge-base article**. Slack is only the notification surface —
Zammad is the truth.

You reach Zammad over its REST API with `curl` (and `jq` to read fields). Two
environment variables are already in your process (from the systemd
EnvironmentFile), so never print them:

- `ZAMMAD_URL` — base URL, e.g. `https://zammad.<subdomain>`
- `ZAMMAD_API_TOKEN` — your API token

Every request carries `Authorization: Token token=$ZAMMAD_API_TOKEN`. Standard
call shape:

```bash
curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/<path>"
```

---

## 1. The one rule: dedupe BEFORE you create

An incident that is already open must be **appended to**, never re-opened as a
duplicate. Before creating anything, search for an open ticket that matches the
same underlying problem.

Give every incident a stable **`finding_key`** — a deterministic identifier for
"this exact problem", built from three parts:

```
finding_key = <source>:<rule>:<entity>
```

- **source** — where the finding came from (e.g. `splunk`, `proxmox`, `unifi`).
- **rule** — the specific detection/condition (e.g. `ingest-stalled`,
  `disk-pressure`, `cert-expiring`). Same rule name every time — do not
  paraphrase it per occurrence.
- **entity** — the one thing it is about, as `key=value` (e.g. `index=firewall`,
  `host=pve1`, `vhost=llm`). Pick the narrowest entity that still groups repeat
  occurrences of the *same* problem.

**Normalize** the assembled key so the same problem always renders identical
bytes: lowercase everything, use `:` as the only field separator, and replace
any whitespace with `-`. So a Splunk saved search `Ingest Stalled` on
`index=Firewall` becomes `splunk:ingest-stalled:index=firewall` — never
`splunk:Ingest Stalled:index=Firewall`. A drifting key defeats the dedup.

Put it in the ticket title as a searchable `fk:` token, e.g.
`fk:splunk:ingest-stalled:index=firewall`. Because the three parts are
deterministic, the same problem always produces the same `finding_key`, so a
search reliably finds prior occurrences:

```bash
# state.name:(new OR open) keeps it to LIVE incidents; the finding_key pins the problem.
curl -sS -G -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  --data-urlencode 'query=state.name:(new OR open) AND title:"fk:splunk:ingest-stalled:index=firewall"' \
  --data-urlencode 'limit=5' --data-urlencode 'expand=false' \
  "$ZAMMAD_URL/api/v1/tickets/search"
```

A paraphrased `fk:` key is the known failure mode — a human or a differently
worded run can title the same problem slightly differently, and the exact-match
search above then misses it, creating a duplicate. Always run a second,
backstop search on a **normalized title prefix**: the first 5 words of the
human-summary part of the title, lowercased, punctuation stripped, joined on
spaces, matched across every live state:

```bash
# Backstop: catches a paraphrased fk: key that the exact search above would miss.
curl -sS -G -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  --data-urlencode 'query=state.name:(new OR open OR "pending close") AND title:"ingest stalled on firewall index"' \
  --data-urlencode 'limit=5' --data-urlencode 'expand=false' \
  "$ZAMMAD_URL/api/v1/tickets/search"
```

Keep results bounded (`limit` small, `expand=false`) — do NOT pull full ticket
bodies or article lists into your context. If either search returns a match →
**append** (Section 3). If neither does → **create** (Section 2).

---

## 2. Create an incident

File the ticket **as yourself**: Zammad requires a customer on agent-created
tickets, and using your own token identity routes the ticket into your
dedicated service org — auto-filed tickets stay in their own container,
bulk-manageable without touching anything else. Look your login up once per
session and reuse it:

```bash
ZAMMAD_SELF=$(curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  "$ZAMMAD_URL/api/v1/users/me" | jq -r .login)
```

Every ticket has a **type**, chosen before you write the article, because the
type decides how the ticket can ever be closed (Section 5):

| `type` | What it covers | `resolved_when` |
| --- | --- | --- |
| `outage` | A service or probe was observed down | `probe:<bounded query>` — the query that shows recovery |
| `weakness` | A security or config finding, fixed by code | `url:<PR or task URL>` — the change that fixes it. Unknown yet → `url:pending`, and the next review pass MUST fill it in once the PR/task exists |
| `hygiene` | Cleanup, doc, or to-do work with no recovery query | `ttl:<days>` — default `14` |

The first article's body MUST begin with these two lines, verbatim shape,
before any other content:

```
type: outage|weakness|hygiene
resolved_when: probe:<bounded query> | url:<PR or task URL> | ttl:<days>
```

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets" -d '{
    "title": "fk:<source>:<rule>:<entity> — <human summary>",
    "group": "Incidents",
    "priority_id": <P>,
    "customer": "'"$ZAMMAD_SELF"'",
    "detection_method": "<probe|user-report|alert|agent|other>",
    "source_issue": "<URL, or omit if none known yet>",
    "article": {
      "subject": "<short>",
      "body": "type: <outage|weakness|hygiene>\nresolved_when: <probe:... | url:... | ttl:...>\n\n<what you observed, the bounded query, the numbers>",
      "type": "note",
      "internal": true
    }
  }'
```

`detection_method` is the ticket custom field recording how the finding
surfaced: `probe` (a scheduled check), `user-report`, `alert` (Splunk-sourced),
`agent` (found during a self-audit pass), or `other`. Set `source_issue` to the
originating URL whenever one is already known (a Splunk alert link, a PR); a
`weakness` ticket without one yet gets it filled in during triage or resolve
once the fixing PR/task exists.

Then tag the new ticket `auto-managed` **and** `type:<x>` so the lifecycle in
Section 5 can own it and later passes can find it by type without re-parsing
the article body:

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/add" \
  -d '{"object": "Ticket", "o_id": <id>, "item": "auto-managed"}'
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/add" \
  -d '{"object": "Ticket", "o_id": <id>, "item": "type:<outage|weakness|hygiene>"}'
```

**Severity mapping.** A Splunk finding carries a native `severity` (notable /
alert level). Map it straight to the ticket `priority_id`:

| Splunk `severity` | `priority_id` | Zammad name | Reads as |
| --- | --- | --- | --- |
| `critical` | `4` | 4 critical | P1 — server/service down, security |
| `high` | `3` | 3 high | P2 — major degradation |
| `medium` | `2` | 2 normal | P3 — minor / single-source |
| `low` / `info` / `informational` | `1` | 1 low | P4 — cosmetic / low |

A non-Splunk source without a native severity uses the same P-level judgement
to pick the `priority_id`. Always file into the **`Incidents`** group. Keep the
article factual and numbers-backed — same discipline as a splunk-monitor alert,
no walls of text, no raw events. Creating a ticket stays a single API call plus
the two tag calls above — never gate ticket creation behind an approval step or
a rate limit.

---

## 3. Append to an existing incident (the narrative)

Investigation notes, new readings, and status changes go on the **existing
ticket's thread** — never a new ticket. Add an article:

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/ticket_articles" -d '{
    "ticket_id": <id>,
    "subject": "triage update",
    "body": "<new finding + the bounded query + numbers>",
    "type": "note", "internal": true
  }'
```

Escalate or de-escalate by updating the ticket's priority/state:

```bash
curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
  -d '{"priority_id": 3}'
```

---

## 4. Triage — runs every review pass, on every `new` ticket

A ticket sitting in `new` with no `type:` tag and no `resolved_when` is a
ticket nothing can ever close — it has no closure condition to evaluate.
Every review pass, for every ticket in state `new`:

1. **Move it to `open`** (`state_id` 2) — "leave it in `new`" is not a valid
   outcome of a review pass:

   ```bash
   curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
     -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
     -d '{"state_id": 2}'
   ```

2. **If it lacks a `type:<x>` tag**, classify it from the title and article
   body (Section 2's table) and tag it in the same pass:

   ```bash
   curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
     -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/add" \
     -d '{"object": "Ticket", "o_id": <id>, "item": "type:<outage|weakness|hygiene>"}'
   ```

3. **If the first article lacks a `resolved_when:` line**, append an article
   supplying both lines so the ticket has a closure condition:

   ```bash
   curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
     -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/ticket_articles" -d '{
       "ticket_id": <id>,
       "subject": "triage: classification",
       "body": "type: <outage|weakness|hygiene>\nresolved_when: <probe:... | url:... | ttl:...>",
       "type": "note", "internal": true
     }'
   ```

Triage never closes or auto-manages a ticket by itself — it only gets the
ticket into a state (`open`, typed, with a `resolved_when`) that Section 5 can
evaluate.

---

## 5. Resolve — close the ticket AND capture the knowledge

Closure is **per-type**, driven by the ticket's `resolved_when` condition
(Section 2). Every close, regardless of type, MUST set the `root_cause` custom
field to one causal sentence in the same `PUT` — a restatement of the title
("ingest was stalled") is not a root cause; say why it stalled.

### 5a. `outage` — recovery probe + quiet period

When the problem is **confirmed recovered** (verified with a bounded query,
not just "it went quiet") and the Section 6 quiet-period has fully elapsed:

```bash
curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
  -d '{"state_id": 4, "root_cause": "<one causal sentence>", "article": {"body": "recovered — <verifying query + numbers>", "type": "note", "internal": true}}'
```

### 5b. `weakness` — resolved_when URL is merged/done

Resolve when the `resolved_when` URL now shows the fix landed:

```bash
# GitHub PR
gh pr view <pr-url> --json state,mergedAt
# Vikunja task
curl -sS -H "Authorization: Bearer $VIKUNJA_TOKEN" "$VIKUNJA_URL/api/v1/tasks/<id>" | jq '.done'
```

If `state == "MERGED"` (non-null `mergedAt`) or the task's `done` is `true`,
close it, citing the checked URL and its state in the article:

```bash
curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
  -d '{"state_id": 4, "root_cause": "<one causal sentence>", "article": {"body": "resolved — <url> merged/done, verified via <gh pr view | GET task>", "type": "note", "internal": true}}'
```

### 5c. `hygiene` — ttl elapsed → pending close, not closed

When the `ttl:<days>` window has elapsed, do NOT close directly — move it to
`pending close` (`state_id` 6) with a 7-day grace window and record why:

```bash
curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
  -d '{"state_id": 6, "pending_time": "'"$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)"'", "article": {"body": "auto-pending-close: ttl of <n> days elapsed with no further occurrence", "type": "note", "internal": true}}'
```

Zammad's own scheduler closes the ticket when `pending_time` arrives; a human
bouncing the ticket back to `open` before then cancels the pending-close.
`root_cause` is set at that point, when the ticket actually reaches `closed`
(Zammad's scheduler does the state transition, not this skill) — record it on
the ticket the next time a review pass observes it closed via the scheduler,
or set it up front in the `pending close` article if the cause is already
known.

### 5d. Likely-resolved-but-unproven — any type

A ticket you believe is fixed but cannot fully prove (the probe is flaky, the
PR merged but you haven't verified the deployed behavior) goes to
`pending close` (`state_id` 6, +7 days) with the evidence you do have — **never
straight to `closed`**. Use the same call shape as 5c.

### Knowledge capture (any type, on actual close)

If the incident taught something reusable (a root cause, a fix, a runbook),
publish a **knowledge-base article** so the next occurrence is faster. Fetch
the KB + a category id first, then create the answer:

```bash
curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" "$ZAMMAD_URL/api/v1/knowledge_bases"   # ids
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' \
  "$ZAMMAD_URL/api/v1/knowledge_bases/<kb_id>/answers" -d '{
    "category_id": <cat_id>,
    "translations": [{"title": "<what broke> — <fix>", "body": "<RCA + runbook>", "kb_locale_id": <locale_id>}]
  }'
```

If the KB API shape has drifted (Zammad versions vary here), record the RCA
as an internal article on the closed ticket instead and note that the KB
article is still to be written — never drop the knowledge.

---

## 6. Auto-managed lifecycle — quiet-period auto-close that yields to humans

Tickets you open are tagged `auto-managed` (Section 2). That tag is your license
to close them without a human — and the moment a human engages, you give it up.

**Yield to human touch — check this before ANY auto-close.** Learn your own
account id once per session, then look for an article written by anyone else:

```bash
me=$(curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" "$ZAMMAD_URL/api/v1/users/me" | jq .id)
# true = a human authored an article on the thread
curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  "$ZAMMAD_URL/api/v1/ticket_articles/by_ticket/<id>" \
  | jq --argjson me "$me" 'any(.[]; .created_by_id != $me)'
# true = a human made the last change to the ticket itself (state, priority, owner)
curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  "$ZAMMAD_URL/api/v1/tickets/<id>" \
  | jq --argjson me "$me" '.updated_by_id != $me'
```

A ticket is **human-touched** if either check is `true` — any article
`created_by_id` other than you, or the ticket's own `updated_by_id` is not you
(a human changed its state, priority, or owner), or its `owner_id` is a real
operator. When that happens, **yield**: remove the tag and stop auto-managing —
never change its state or priority again. The human owns it now.

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/remove" \
  -d '{"object": "Ticket", "o_id": <id>, "item": "auto-managed"}'
```

**Auto-close conditions — ALL must hold:**

1. The ticket is still tagged `auto-managed` (verify:
   `GET /api/v1/tags?object=Ticket&o_id=<id>`).
2. No human touch (the check above returns `false`).
3. The ticket's type-specific closure condition is met (Section 5): `outage`
   recovery confirmed, `weakness` PR/task merged or done, or `hygiene` ttl
   elapsed into `pending close`.
4. For `outage` specifically, the **quiet period** has fully elapsed: no new
   occurrence of this `finding_key` for at least `ZAMMAD_QUIET_HOURS` (the
   skill parameter, default 72) — one quiet reading is not enough; re-check
   after the window.

Only then close it (or move it to `pending close`) with the Section 5 article.
Leave the `auto-managed` tag on the closed ticket so the record shows the agent
resolved it. If any condition fails, do nothing this cycle and re-evaluate next
cycle.

---

## 7. Guardrails

1. **Dedupe first, always.** Search open tickets by `finding_key` AND the
   normalized-title backstop before creating. One incident = one ticket;
   everything else is an article on it.
2. **Dry-run honours `ZAMMAD_DRY_RUN`.** When it is set, do NOT send any write
   (create, update, close, tag) — print the method, path, and body you WOULD
   send, then continue. Reads still run, so dedup and yield checks stay honest.
3. **Rate-limit writes.** At most one create or state change per `finding_key`
   per cycle. Never loop-create or loop-close; if unsure, do nothing and record.
4. **Bounded reads.** `limit` small, `expand=false`, never pull full ticket or
   article lists into context — same anti-context-spam contract as splunk-monitor.
5. **Numbers, not prose.** Every article carries the bounded query and the
   figures that justify it.
6. **Never print `$ZAMMAD_API_TOKEN`** (or any secret) into a ticket, article,
   KB page, log, or Slack message.
7. **Confirm recovery before closing.** A quiet signal is not a recovered one —
   verify with a query, and only auto-close under Section 6's full conditions.
8. **Yield to humans.** An `auto-managed` ticket a human has touched is theirs —
   drop the tag, never auto-close it.
9. **Every ticket in `new` gets triaged, every pass.** "Leave it in `new`" is
   never a valid outcome of a review pass (Section 4).
10. **Never set `pending close` without an article stating why.**
11. **Never close a ticket without setting `root_cause`.** A restatement of the
    title is not a root cause.
12. **Zammad is the record; Slack is the notification.** After you open or
    update a ticket, the splunk-monitor delivery step still DMs the operator —
    include the ticket URL (`$ZAMMAD_URL/#ticket/zoom/<id>`) so they can jump
    straight to it.
