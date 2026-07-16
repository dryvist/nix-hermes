---
name: dryvist-zammad-incidents
description: Open, update, dedupe, resolve, and document homelab incidents in Zammad (the ITSM system of record) via its REST API — the durable ticket + knowledge-base layer behind the splunk-monitor alerts
version: 1.0.0
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

You reach Zammad over its REST API with `curl`. Two environment variables are
already in your process (from the systemd EnvironmentFile), so never print them:

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

Give every incident a stable **fingerprint** — a short, deterministic tag for
"this exact problem" (e.g. `fp:splunk-ingest-stalled:index=firewall`), and put
it in the ticket title. Then a search finds prior occurrences:

```bash
# state.name:(new OR open) keeps it to LIVE incidents; the fingerprint pins the problem.
curl -sS -G -H "Authorization: Token token=$ZAMMAD_API_TOKEN" \
  --data-urlencode 'query=state.name:(new OR open) AND title:"fp:splunk-ingest-stalled*"' \
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
    "title": "fp:<fingerprint> — <human summary>",
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

**Severity mapping** — your P-level maps to Zammad `priority_id`:

| You call it | `priority_id` | Zammad name |
| --- | --- | --- |
| P1 (server/service down, security) | `4` | 4 critical |
| P2 (major degradation) | `3` | 3 high |
| P3 (minor / single-source) | `2` | 2 normal |
| P4 (cosmetic / low) | `1` | 1 low |

Always file into the **`Incidents`** group. Keep the article factual and
numbers-backed — same discipline as a splunk-monitor alert, no walls of text,
no raw events.

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

## 5. Guardrails

1. **Dedupe first, always.** Search open tickets by fingerprint before creating.
   One incident = one ticket; everything else is an article on that ticket.
2. **Bounded reads.** `limit` small, `expand=false`, never pull full ticket or
   article lists into context — same anti-context-spam contract as splunk-monitor.
3. **Numbers, not prose.** Every article carries the bounded query and the
   figures that justify it.
4. **Never print `$ZAMMAD_API_TOKEN`** (or any secret) into a ticket, article,
   KB page, log, or Slack message.
5. **Confirm recovery before closing.** A quiet signal is not a recovered one —
   verify with a query.
6. **Zammad is the record; Slack is the notification.** After you open or update
   a ticket, the splunk-monitor delivery step still DMs the operator — include
   the ticket URL (`$ZAMMAD_URL/#ticket/zoom/<id>`) so they can jump straight to it.
