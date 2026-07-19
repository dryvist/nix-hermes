---
name: dryvist-openrouter-models
description: Discover current leading OpenRouter models and live prices (public keyless API), select an escalation model for complicated work or advanced coding, call it through the LiteLLM router within a $1/day budget, and request onboarding of models the router does not serve yet
version: 1.0.0
author: dryvist homelab
license: MIT
platforms: [linux]
metadata:
  hermes:
    category: research
    tags: [openrouter, models, pricing, escalation, budget, dryvist]
    related_skills: [dryvist/github-issues]
---

# dryvist openrouter-models

Your resident local brain handles routine work. For **complicated reasoning or
advanced coding** where a stronger frontier model would genuinely change the
outcome, you may escalate to an OpenRouter model — a deliberate per-call
choice, never an automatic on-error fallback. This skill teaches you to find
what is currently available, what it costs, and how to use it within budget.

## Budget: $1.00 per day (hard rule)

- Track your spend in memory under key `openrouter-spend-<YYYY-MM-DD>`:
  after each paid call, estimate cost from the response's token usage times
  the per-token prices you discovered, and add it to the day's total.
- Before any paid call, check the day's total. At or above $1.00: use the
  resident brain or a `:free` variant instead, and note the deferral.
- Prefer `:free` variants whenever they are adequate for the task. Never run
  a long unattended loop on a paid model.

## Discover current models and prices (keyless, public)

The OpenRouter model catalog is public — no API key involved:

```sh
curl -s https://openrouter.ai/api/v1/models | jq '
  .data[] | {id, context_length,
             prompt_usd_per_mtok: ((.pricing.prompt | tonumber) * 1000000),
             completion_usd_per_mtok: ((.pricing.completion | tonumber) * 1000000)}'
```

Useful selections:

- Cheapest strong coders: filter ids matching your task domain, sort by
  `completion_usd_per_mtok`, read the top few.
- Free tier: `.data[] | select(.id | endswith(":free")) | .id`.
- For "what is currently leading", combine this catalog with a short web
  check (your web toolset) of OpenRouter's public rankings — the catalog is
  ground truth for price and context length; rankings are opinion.

Refresh discovery when you actually need it (prices change), not on a
schedule. Cache the day's findings in memory rather than re-fetching per call.

## Use a model — always through the router

Every model call goes through the homelab LLM router (your normal endpoint).
The OpenRouter credential lives in the router, never on this guest. Request
the model by its **exact id** as the router serves it. Registered today:

- `deepseek/deepseek-v4-flash` — paid, 1M context. The workhorse escalation.
- `nvidia/nemotron-3-ultra-550b-a55b:free` — free tier, rate-limited, and the
  provider logs prompt/session data on `:free` — **never send confidential
  material through it**.

A model id the router does not serve will fail — that is the signal to use
the request lane below, not to retry blindly.

## Request a model the router does not serve yet

Onboarding a new OpenRouter model is an infrastructure change (a per-model
credential plus a router registration), so it is not self-serve. When
discovery shows a model clearly worth having, file ONE GitHub issue in
`dryvist/ansible-proxmox-ai` titled `[hermes-model-request] <exact-model-id>`
containing: the exact OpenRouter id, current prompt/completion price per
1M tokens, context length, the concrete task class that justifies it, and the
expected spend inside your $1/day budget. Check for an existing open request
first — never duplicate. Real model ids only; never propose a generic alias.

## Attribution

State the model(s) you actually used in every delivered message (see your
persona's attribution rule) — the resident brain by name when you did not
escalate, and every escalation model when you did.
