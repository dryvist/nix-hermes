---
name: dryvist-zammad-incidents
description: Open, update, dedupe, resolve, and auto-close homelab incidents in Zammad (the ITSM system of record) via its REST API — the durable ticket + knowledge-base layer behind the splunk-monitor alerts, keyed on a stable finding_key and lifecycle-tagged so agent-managed tickets yield to any human touch
version: 1.1.0
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

Keep results bounded (`limit` small, `expand=false`) — do NOT pull full ticket
bodies or article lists into your context. If the search returns a match →
**append** (Section 3). If not → **create** (Section 2).

---

## 2. Create an incident

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets" -d '{
    "title": "fk:<source>:<rule>:<entity> — <human summary>",
    "group": "Incidents",
    "priority_id": <P>,
    "article": {
      "subject": "<short>",
      "body": "<what you observed, the bounded query, the numbers>",
      "type": "note",
      "internal": true
    }
  }'
```

Then tag the new ticket `auto-managed` so the lifecycle in Section 5 can own it:

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/add" \
  -d '{"object": "Ticket", "o_id": <id>, "item": "auto-managed"}'
```

**Severity mapping.** A Splunk finding carries a native `severity` (notable /
alert level). Map it straight to the ticket `priority_id`:

| Splunk `severity` | `priority_id` | Zammad name | Reads as |
| --- | --- | --- | --- |
| `critical` | `4` | 4 critical | P1 — server/service down, security |
| `high` | `3` | 3 high | P2 — major degradation |
| `medium` | `2` | 2 normal | P3 — minor / single-source |
| `low` | `1` | 1 low | P4 — cosmetic / low |
| `info` / `informational` | — | — | below threshold — record, do NOT open a ticket |

A non-Splunk source without a native severity uses the same P-level judgement
to pick the `priority_id`. Always file into the **`Incidents`** group. Keep the
article factual and numbers-backed — same discipline as a splunk-monitor alert,
no walls of text, no raw events.

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

## 4. Resolve — close the ticket AND capture the knowledge

When the problem is **confirmed recovered** (verified with a bounded query, not
just "it went quiet"):

1. Close the ticket (`state_id` 4 = closed on a default Zammad install; confirm
   via `GET /api/v1/ticket_states` if unsure):

   ```bash
   curl -sS -X PUT -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
     -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tickets/<id>" \
     -d '{"state_id": 4, "article": {"body": "recovered — <verifying query + numbers>", "type": "note", "internal": true}}'
   ```

2. If the incident taught something reusable (a root cause, a fix, a runbook),
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

## 5. Auto-managed lifecycle — quiet-period auto-close that yields to humans

Tickets you open are tagged `auto-managed` (Section 2). That tag is your license
to close them without a human — and the moment a human engages, you give it up.

**Yield to human touch — check this before ANY auto-close.** Learn your own
account id once per session, then look for an article written by anyone else:

```bash
me=$(curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" "$ZAMMAD_URL/api/v1/users/me" | jq .id)
# true = a human has touched the thread
curl -sS -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  "$ZAMMAD_URL/api/v1/ticket_articles/by_ticket/<id>" \
  | jq --argjson me "$me" 'any(.[]; .created_by_id != $me)'
```

A ticket is **human-touched** if any article `created_by_id` is not you, or its
`owner_id` is a real operator. When that happens, **yield**: remove the tag and
stop auto-managing — the human owns it now.

```bash
curl -sS -X POST -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  -H 'Content-Type: application/json' "$ZAMMAD_URL/api/v1/tags/remove" \
  -d '{"object": "Ticket", "o_id": <id>, "item": "auto-managed"}'
```

**Auto-close conditions — ALL must hold:**

1. The ticket is still tagged `auto-managed` (verify:
   `GET /api/v1/tags?object=Ticket&o_id=<id>`).
2. No human touch (the check above returns `false`).
3. Recovery is **confirmed** with a bounded query (Section 4) — never on a merely
   quiet signal.
4. The **quiet period** has fully elapsed: no new occurrence of this
   `finding_key` for at least `ZAMMAD_QUIET_MINUTES` (default 60) — one quiet
   reading is not enough; re-check after the window.

Only then close it with the Section 4 recovery article. Leave the `auto-managed`
tag on the closed ticket so the record shows the agent resolved it. If any
condition fails, do nothing this cycle and re-evaluate next cycle.

---

## 6. Guardrails

1. **Dedupe first, always.** Search open tickets by `finding_key` before
   creating. One incident = one ticket; everything else is an article on it.
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
   verify with a query, and only auto-close under Section 5's full conditions.
8. **Yield to humans.** An `auto-managed` ticket a human has touched is theirs —
   drop the tag, never auto-close it.
9. **Zammad is the record; Slack is the notification.** After you open or update
   a ticket, the splunk-monitor delivery step still DMs the operator — include
   the ticket URL (`$ZAMMAD_URL/#ticket/zoom/<id>`) so they can jump straight to it.
