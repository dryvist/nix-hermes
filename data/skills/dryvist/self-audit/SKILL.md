---
name: dryvist-self-audit
description: Audit your own operation as the homelab agent — sweep Splunk for your own errors, read your own Slack output back and critique it, verify memory/hindsight/cron/kanban are actually healthy, file kanban correction cards for every defect found, and escalate severe findings to Zammad
version: 1.0.0
author: dryvist homelab
license: MIT
platforms: [linux]
metadata:
  hermes:
    category: research
    tags: [self-audit, slack, splunk, observability, kanban, dryvist]
    related_skills: [dryvist/splunk-monitor, dryvist/zammad-incidents, dryvist/github-issues]
---

# dryvist self-audit

You are auditing **yourself**. Every run is a fresh session with no memory of the
last one, so your first act is always to recall your fingerprint (Section 4), and
your last act is always to save it back. Between those: find your own errors,
critique your own output, prove your own subsystems work — and turn every real
defect into a tracked correction.

The loop's output is **tracked issues**, not silent fixing. You observe, file,
and escalate; the board's workers do the fixing. Do not attempt infrastructure
repairs from this job.

---

## 1. Read your own Slack output back

Your posts are delivered through a Slack bot whose token is in your environment
as `SLACK_BOT_TOKEN`. Reading uses the Slack Web API with plain `curl` — there
is no dedicated read tool:

```bash
curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  "https://slack.com/api/conversations.history?channel=$CHANNEL_ID&oldest=$TS&limit=100"
```

Rules for this section:

- **Channel ids come from your env first**: `SLACK_HERMES_ALL_CHANNEL`,
  `SLACK_HERMES_ISSUES_CHANNEL`, `SLACK_HERMES_NOISE_CHANNEL`,
  `SLACK_SPLUNK_CHANNEL` (may be empty). If an id you need is unset, resolve it
  once via `conversations.list` (paginated, `limit=200`) and remember it in your
  fingerprint so later runs do not re-list.
- **Fetch only the delta.** Pass `oldest=` from your fingerprint's per-channel
  timestamp. Never page all history.
- **Bound yourself**: at most ~3 pages of 100 per channel per run. If
  `has_more` is still true after that, note it in the fingerprint and catch up
  next run. On `rate_limited` (or HTTP 429), sleep the given `Retry-After`
  seconds **once**; if it repeats, stop fetching and record the gap.
- **Only your own messages matter.** Filter by `bot_id`/`user` from `auth.test`
  against `SLACK_BOT_TOKEN`.
- If a fetch fails (`ok: false` other than rate limiting), that itself is a
  finding (Slack read path broken) — record it and continue with the rest of
  the audit.

### What to look for in your own output

- **Repetition across runs** — the same substantive content posted twice. This
  means some job's memory-key recall/save cycle is not working.
- **Broken `[SILENT]` discipline** — routine jobs posting when they had nothing
  new, or going quiet when something was wrong.
- **Garbled or truncated output** — cut-off sentences, raw tool dumps leaking
  into posts, mojibake, empty posts. These point at upstream model or token
  limits (the free preset rung is a suspect).
- **Wrong routing** — digests landing in issues, alerts landing in noise,
  threads left dangling.
- **Unkept promises** — any post claiming a follow-up ("filing a card",
  "opening a ticket") where no such card/ticket exists.

## 2. Sweep Splunk for your own errors

Your own traces ship OTLP → Cribl → Splunk, so your failures are searchable.
Apply **exactly the same hard query rails** as the `dryvist/splunk-monitor`
skill: aggregate or `| head N` (N ≤ 100) only, explicit narrow time window
**written inline in SPL** (e.g. `earliest=-12h` — never trust the MCP's
`earliest` argument, it is dropped), `tstats` for inventory, project only what
you need, one question per query.

On your first runs the index/sourcetype names for your traces may be unknown —
discover them once with bounded metadata queries (`get_indexes`,
`get_sourcetypes`, a `| tstats count … by index, sourcetype` filtered on
`hermes`/agent-ish names), then store the confirmed coordinates in your
fingerprint. Sweep for:

- error/warning-level events from your own guest and services over the window;
- repeated identical signatures (cluster by normalized signature — strip
  timestamps, pids, ids, numbers — one line per signature naming its count);
- gaps: a subsystem that used to log and has gone silent is as suspicious as
  one that logs errors.

## 3. Prove your subsystems work

Each probe must produce evidence, not vibes. A probe that cannot run is itself
a finding about that subsystem.

| Subsystem | Proof |
| --- | --- |
| Memory / Hindsight | Non-fatal `hermes memory status`; then a live round-trip: recall `self-audit-last` (must succeed; empty result on first ever run is valid), and save the updated fingerprint at the end (a failed save = memory write path broken). |
| Cron fleet | `hermes cron list --all`: every core seeded job present and not paused-by-drift; note jobs with recent failure streaks if the listing shows them. |
| Kanban | Inspect the board (`hermes kanban --help` first if unsure): stuck `running` cards older than their expected duration, backlog growing unboundedly, cards that reference jobs which no longer exist. |
| Splunk MCP | Any successful bounded query in Section 2 doubles as this probe; zero successful queries = finding. |
| Slack delivery | Your Section 1 fetches double as this probe; total fetch failure = finding. |

## 4. The fingerprint (memory key `self-audit-last`)

Recall it at start, save it at end. Keep it compact but structured:

```
last_run_utc, splunk {index, sourcetype, known_signatures[]},
slack {per-channel oldest ts, bot_id},
down_counts {subsystem: consecutive-run count},
known_cards [titles already filed]
```

`down_counts` is how "severe" is decided without cross-run state anywhere else:
increment a subsystem's counter when this run finds it unhealthy, reset to zero
when a run proves it healthy again.

## 5. Routing findings

1. **Dedupe first** — against your fingerprint's known signatures/cards, open
   kanban cards, and (for severe) open Zammad tickets. Re-finding the same
   thing every run is failure, not diligence.
2. **Every actionable defect → one kanban card** (`hermes kanban create`),
   titled `[self-audit] <subsystem>: <one-line problem>`, body carrying: the
   evidence (bounded query + numbers, message permalinks), the suspected cause,
   and a concrete suggested fix. One defect per card.
3. **Severe → Zammad too** (via `dryvist/zammad-incidents`): a subsystem whose
   `down_counts` reaches **2 consecutive runs**, or anything security-shaped.
   Search open tickets for the fingerprint before opening; append to the
   existing ticket instead of duplicating. Numbers-backed, same as alerts.
4. **Final response = the digest**: one concise post covering what was checked,
   what was found, what was filed (card titles + ticket ids). Delivered to the
   issues channel. When everything is healthy **reply exactly `[SILENT]`** —
   a clean audit costs zero notifications.

## 6. Guardrails

1. **Read-only on the world; writes only to memory, kanban, Zammad.** No config
   edits, no restarts, no cron mutations beyond reading.
2. **Bounded everything**: queries, pages, turns. Hand deep investigations off
   via the fingerprint, never sprawl.
3. **Never leak secrets** — tokens, credentials, or sensitive message content —
   into cards, tickets, posts, or memory. Reference, redact, permalink.
4. **Signal, not noise, both directions**: don't pad the digest, don't bury a
   real defect under `[SILENT]`.
