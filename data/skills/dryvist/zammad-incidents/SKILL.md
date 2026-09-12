---
name: dryvist-zammad-incidents
description: Open, update, dedupe, triage, resolve, and auto-close typed homelab incidents in Zammad (ITSM system of record) via REST — keyed on finding_key, typed outage/weakness/hygiene with per-type closure, lifecycle-tagged to yield to human touch
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

Zammad is the homelab's **incident-management system of record**: a
confirmed problem gets a **ticket**, a resolved one gets a **knowledge-base
article**. Slack is only the notification surface.

Reach it over REST with `curl`/`jq`. `ZAMMAD_URL` and `ZAMMAD_API_TOKEN` are
already in your process (systemd EnvironmentFile) — never print them:

```bash
curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/<path>"
```

---

## 1. The one rule: dedupe BEFORE you create

An open incident gets **appended to**, never re-opened as a duplicate.
Search first for a matching open ticket.

Give every incident a stable **`finding_key`**: `<source>:<rule>:<entity>` —
source (`splunk`, `proxmox`, `unifi`...), rule (the detection name, unchanged
across occurrences), entity as `key=value` (the narrowest thing that still
groups repeats of the same problem).

**Normalize**: lowercase, `:` as the only separator, whitespace → `-`. A
Splunk search `Ingest Stalled` on `index=Firewall` becomes
`splunk:ingest-stalled:index=firewall`, never the raw casing — drift here
defeats dedup.

Put it in the title as `fk:splunk:ingest-stalled:index=firewall`, then search
for it (`state.name:(new OR open)` keeps it to LIVE incidents):

```bash
curl -sS -G -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  --data-urlencode 'query=state.name:(new OR open) AND title:"fk:splunk:ingest-stalled:index=firewall"' \
  --data-urlencode 'limit=5' --data-urlencode 'expand=false' \
  "$ZAMMAD_URL/api/v1/tickets/search"
```

A paraphrased `fk:` key can slip past the exact match, so also run a
backstop: same shape, `query` swapped for a normalized title prefix (first 5
words of the summary, lowercased, punctuation stripped) across every live
state. Either hits → **append** (Section 3); neither does → **create**
(Section 2).

---

## 2. Create an incident

File **as yourself** — Zammad requires a customer, and your identity routes
it into your dedicated service org. Look your login up once per session:

```bash
ZAMMAD_SELF=$(curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  "$ZAMMAD_URL/api/v1/users/me" | jq -r .login)
```

Every ticket has a **type**, chosen before you write the article — it decides
how the ticket can close (Section 5):

| `type` | Covers | `resolved_when` |
| --- | --- | --- |
| `outage` | Service/probe observed down | `probe:<bounded query>` showing recovery |
| `weakness` | Security/config finding, fixed by code | `url:<PR or task URL>`. Unknown yet → `url:pending`, filled in at next triage |
| `hygiene` | Cleanup/doc/to-do, no recovery query | `ttl:<days>`, default `14` |

The first article's body MUST open with these two lines, verbatim shape:

```
type: outage|weakness|hygiene
resolved_when: probe:<bounded query> | url:<PR or task URL> | ttl:<days>
```

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets" -d '{
    "title": "fk:<source>:<rule>:<entity> — <human summary>", "group": "Incidents",
    "priority_id": <P>, "customer": "'"$ZAMMAD_SELF"'",
    "detection_method": "<probe|user-report|alert|agent|other>",
    "source_issue": "<URL, or omit if none known yet>",
    "article": {
      "subject": "<short>",
      "body": "type: <outage|weakness|hygiene>\nresolved_when: <probe:... | url:... | ttl:...>\n\n<what you observed, the bounded query, the numbers>",
      "type": "note", "internal": true
    }
  }'
```

`detection_method`: `probe`, `user-report`, `alert` (Splunk), `agent`
(self-audit), or `other`. Set `source_issue` to the originating URL when
known; fill it in for `weakness` tickets once the fixing PR/task exists.

Tag it `auto-managed` **and** `type:<x>` so Section 5/6 can own it without
re-parsing the article body:

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/add" \
  -d '{"object": "Ticket", "o_id": <id>, "item": "auto-managed"}'
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/add" \
  -d '{"object": "Ticket", "o_id": <id>, "item": "type:<outage|weakness|hygiene>"}'
```

**Severity mapping** — Splunk `severity` → `priority_id`: `critical`→`4`
(P1 down/security), `high`→`3` (P2 major degradation), `medium`→`2` (P3
minor/single-source), `low`/`info`→`1` (P4 cosmetic). Non-Splunk sources use
the same P-level judgement.

File into **`Incidents`**, articles factual and numbers-backed, no raw
events. Creation stays one API call plus the two tag calls — never gate it
behind approval or a rate limit.

---

## 3. Append to an existing incident (the narrative)

Notes, readings, and status changes go on the **existing thread**, never a
new ticket:

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/ticket_articles" -d '{
    "ticket_id": <id>,
    "subject": "triage update",
    "body": "<new finding + the bounded query + numbers>",
    "type": "note", "internal": true
  }'
```

Escalate with a `PUT` to the same tickets endpoint, `-d '{"priority_id": <P>}'`.

---

## 4. Triage — every review pass, every `new` ticket

A ticket in `new` with no `type:` tag or `resolved_when` has no closure
condition to evaluate. Every pass, for every `new` ticket:

1. **Move to `open`** (`state_id` 2) — leaving it `new` is never valid:

   ```bash
   curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
     -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
     -d '{"state_id": 2}'
   ```

2. **No `type:<x>` tag** → classify from the title/body (Section 2's table),
   tag it the same pass (same shape as Section 2's tag calls).

3. **No `resolved_when:` line** → append an article supplying both lines
   (same shape as Section 3's append, `subject: "triage: classification"`,
   body `type: ...\nresolved_when: ...`).

Triage never closes or auto-manages — it only gets the ticket into a state
Section 5 can evaluate.

---

## 5. Resolve — close the ticket AND capture the knowledge

Closure is **per-type**, driven by `resolved_when` (Section 2). Every close,
any type, MUST set `root_cause` in the same `PUT` to one causal sentence — a
restatement of the title is not a root cause.

### 5a. `outage` — recovery probe + quiet period

Confirmed recovered (a bounded query, not "it went quiet") and Section 6's
quiet period has elapsed:

```bash
curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
  -d '{"state_id": 4, "root_cause": "<one causal sentence>", "article": {"body": "recovered — <verifying query + numbers>", "type": "note", "internal": true}}'
```

### 5b. `weakness` — resolved_when URL is merged/done

Check the `resolved_when` URL: `gh pr view <pr-url> --json state,mergedAt`
for a PR, or `GET $VIKUNJA_URL/api/v1/tasks/<id> | jq .done` for a task.
`state == "MERGED"` or `done == true` → close, citing the checked URL/state:

```bash
curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
  -d '{"state_id": 4, "root_cause": "<one causal sentence>", "article": {"body": "resolved — <url> merged/done, verified via <gh pr view | GET task>", "type": "note", "internal": true}}'
```

### 5c. `hygiene` — ttl elapsed → pending close, not closed

Do NOT close directly — move to `pending close` (`state_id` 6) with a 7-day
grace window:

```bash
curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
  -d '{"state_id": 6, "pending_time": "'"$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)"'", "article": {"body": "auto-pending-close: ttl of <n> days elapsed with no further occurrence", "type": "note", "internal": true}}'
```

Zammad's scheduler closes it when `pending_time` arrives (a human reverting
to `open` cancels it). Set `root_cause` once it reaches `closed` — record it
the next pass that observes the close, or up front if already known.

### 5d. Likely-resolved-but-unproven — any type

Believed fixed but not provable (flaky probe, merged PR but unverified
deploy) → `pending close` (+7 days) with the evidence you have, **never
straight to `closed`**. Same shape as 5c.

### Knowledge capture (on actual close)

If it taught something reusable, fetch a KB/category id
(`GET .../api/v1/knowledge_bases`) and publish an answer:

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' \
  "$ZAMMAD_URL/api/v1/knowledge_bases/<kb_id>/answers" -d '{
    "category_id": <cat_id>,
    "translations": [{"title": "<what broke> — <fix>", "body": "<RCA + runbook>", "kb_locale_id": <locale_id>}]
  }'
```

KB API drifted → record the RCA as an internal article instead — never drop
the knowledge.

---

## 6. Auto-managed lifecycle — quiet-period auto-close that yields to humans

Tickets you open are tagged `auto-managed` (Section 2) — your license to
close without a human; you give it up the moment a human engages.

**Yield check — before ANY auto-close.** Learn your account id once per
session; either query below returning `true` means human-touched:

```bash
me=$(curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" "$ZAMMAD_URL/api/v1/users/me" | jq .id)
curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  "$ZAMMAD_URL/api/v1/ticket_articles/by_ticket/<id>" \
  | jq --argjson me "$me" 'any(.[]; .created_by_id != $me)'   # a human authored an article
curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  "$ZAMMAD_URL/api/v1/tickets/<id>" \
  | jq --argjson me "$me" '.updated_by_id != $me'             # a human changed the ticket
```

Human-touched → **yield**: remove the tag, never touch state/priority
again:

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/remove" \
  -d '{"object": "Ticket", "o_id": <id>, "item": "auto-managed"}'
```

**Auto-close conditions — ALL must hold:** still tagged `auto-managed`
(`GET /api/v1/tags?object=Ticket&o_id=<id>`); no human touch; Section 5's
type-specific closure is met; and for `outage` only, the **quiet period**
has elapsed — no new occurrence of this `finding_key` for `ZAMMAD_QUIET_HOURS`
(default 72h; re-check after the window, one quiet reading isn't enough).

Only then close (or move to `pending close`) with the Section 5 article,
leaving `auto-managed` on it as the record. Any condition fails → do nothing
this cycle, re-evaluate next.

---

## 7. Guardrails

Dedupe, triage, per-type closure with `root_cause`, and yield-to-humans
(Sections 1, 4-6) are load-bearing, not optional. On top of those:

1. `ZAMMAD_DRY_RUN` set → no writes, print method/path/body instead; reads
   still run so dedup/yield checks stay honest.
2. Rate-limit writes: at most one create/state-change per `finding_key` per
   cycle. Unsure → do nothing and record.
3. Bounded reads: small `limit`, `expand=false`, never full bodies/articles.
4. Numbers, not prose — every article carries the query and figures.
5. Never print `$ZAMMAD_API_TOKEN` (or any secret) anywhere.
6. Zammad is the record, Slack the notification — splunk-monitor DMs the
   operator the ticket URL (`$ZAMMAD_URL/#ticket/zoom/<id>`) after each update.
