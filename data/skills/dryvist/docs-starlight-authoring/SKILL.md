---
name: dryvist-docs-starlight-authoring
description: Write correctly-formed docs-starlight content before handing it to docs-pr for delivery
version: 1.0.0
author: dryvist homelab
license: MIT
platforms: [linux]
metadata:
  hermes:
    category: research
    tags: [documentation, dryvist, docs-starlight]
    related_skills: [research/llm-wiki, dryvist/docs-pr]
---

# dryvist docs-starlight-authoring

Content rules for `dryvist/docs-starlight` (Astro Starlight, private KB at
docs.dryvist.com). Use this to shape a page correctly — frontmatter,
components, structure — before handing the change to `docs-pr` for the
actual signed, draft PR. This skill only covers *what to write*; `docs-pr`
covers *how it gets committed and opened*. Always defer to `docs-pr` for
delivery — never `git commit`/`git push` yourself.

Source of truth: this content is kept in sync with the repo-local
`.claude/skills/docs-starlight-authoring/SKILL.md` in `dryvist/docs-starlight`
itself. If the two drift, the repo-local copy wins — it is closer to the
code it describes.

## Do not confuse with the public site

`dryvist/docs` (public, Mintlify) uses a different component library and a
strict PUBLIC-information-only content boundary. Never reuse Mintlify syntax
here, and never route anything sensitive there — `docs-pr`'s privacy-routing
rule (internal/sensitive → docs-starlight only) already enforces this; this
skill covers the *starlight-specific* half of getting the page right.

## Where content lives

```text
src/content/docs/d/
  agent-ops/    conventions/   decisions/    hermes/
  hosts/        incidents/     network/      plans/    runbooks/
```

Pick the existing directory that matches the topic. Never invent a new
top-level section — that is an information-architecture decision for the
human operator, not something to decide mid-run.

## Frontmatter

```yaml
---
title: Page Title
description: One sentence — what this page claims, not "notes about X".
---
```

`sidebar: { order: 0 }` only on a section's own `index.mdx`; at most one
other page per section gets `order: 1`. Everything else stays unordered.
Sidebar badges (`Draft`/`Stub`) are documentation status only — infra
status (live / in soak / declared / planned) belongs in the page's prose,
per that repo's `d/conventions/status-taxonomy` page.

## Components

Import from `@astrojs/starlight/components`:

```mdx
import { Aside, Steps, Card, CardGrid } from '@astrojs/starlight/components';
```

- `<Aside type="note|tip|caution|danger">` for callouts. Use `caution` when
  documenting a target/planned state that is not yet how the system actually
  behaves — a common shape for infra docs written ahead of a rollout.
- `<Steps>` wraps a **plain numbered markdown list** (`1. **Title.** body`) —
  not sub-components. Do not write `<Step title="...">` here; that is the
  Mintlify site's syntax.
- `<Card title="...">` inside `<CardGrid>` for a bottom-of-page "Related"
  section, 2-4 cards.

## Section indexes

A section's `index.mdx` renders its children with the `SectionIndex`
component, never a hand-written list:

```mdx
import SectionIndex from '../../../../components/SectionIndex.astro';

<SectionIndex directory="d/agent-ops" />
```

Copy the `../` depth from a sibling `index.mdx` in the same section rather
than counting — a nested section needs one more `../` than a top-level one.
It throws at build time on an empty or wrong `directory` — that is the
guard working, not a bug.

## Lint constraints docs-pr's PR must pass

- `markdownlint-cli2`: MD013 line length up to 200 chars.
- `gitleaks` on every changed file.
- Package-manager references in prose: bun, never npm.

## Hard rule

Never invent a fact to fill a gap. Every claim on this site must trace to a
live source (a repo, a converge log, a running system) you actually checked
this run. If you cannot verify something, decline that part of the change
and say so in the PR body rather than guessing — `docs-pr`'s "small, sourced"
rule depends on this.
