---
name: dryvist-zammad-incidents
description: Open, update, dedupe, triage, resolve, and auto-close typed homelab incidents in Zammad (ITSM system of record) via REST — keyed on finding_key, typed outage/weakness/hygiene with per-type closure, lifecycle-tagged to yield to human touch
version: 1.3.0
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

Put it in the title as `fk:splunk:ingest-stalled:index=firewall`. Never
hand-build the search or the create: file every incident through the helper,
which searches the live states (`new`, `open`, `pending reminder`,
`pending close`) for that exact key, then **appends** to the match or
**creates** the ticket when there is none (Section 2). It normalizes the key
(lowercase, whitespace → `-`) and refuses one that is not
`fk:<source>:<rule>:<entity>`.

---

## 2. Create an incident

The helper files **as yourself** (`users/me`), into `Incidents`, with the
`auto-managed` and `type:<x>` tags.

Every ticket has a **type**, chosen before you write the article — it decides
how the ticket can close (Section 5):

| `type` | Covers | `resolved_when` |
| --- | --- | --- |
| `outage` | Service/probe observed down | `probe:<bounded query>` showing recovery |
| `weakness` | Security/config finding, fixed by code | `url:<PR or task URL>`. Unknown yet → `url:pending`, filled in at next triage |
| `hygiene` | Cleanup/doc/to-do, no recovery query | `ttl:<days>`, default `14` |

The helper writes the first article as `type:` and `resolved_when:` lines,
then your facts. Put the facts (what you observed, the bounded query, the
numbers) in a file and run:

```bash
python3 "${HERMES_HOME:-$HOME/.hermes}/skills/dryvist/zammad-incidents/scripts/file_incident.py" \
  --key 'fk:<source>:<rule>:<entity>' --summary '<human summary>' \
  --type <outage|weakness|hygiene> \
  --resolved-when '<probe:... | url:... | ttl:...>' \
  --priority <1-4> --detection-method <probe|user-report|alert|agent|other> \
  [--source-issue '<URL>'] --body-file <facts file>
```

It prints `{"action": "appended"|"created", "id": ..., "number": ...}` and
exits non-zero on any API failure. `detection_method`: `probe`,
`user-report`, `alert` (Splunk), `agent` (self-audit), or `other`. Set
`--source-issue` to the originating URL when known; fill it in for
`weakness` tickets once the fixing PR/task exists.

**Severity mapping** — Splunk `severity` → `priority_id`: `critical`→`4`
(P1 down/security), `high`→`3` (P2 major degradation), `medium`→`2` (P3
minor/single-source), `low`/`info`→`1` (P4 cosmetic). Non-Splunk sources use
the same P-level judgement.

File into **`Incidents`**, articles factual and numbers-backed, no raw
events. Creation stays one helper call — never gate it behind approval or a
rate limit.

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
