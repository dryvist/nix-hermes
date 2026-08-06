# nix-hermes — AI Agent Documentation

Builds `packages.<system>.hermes-bundle`: the static content tree (skills +
SOUL.md) the `hermes_agent` Ansible role (ansible-proxmox-apps) copies into
`$HERMES_HOME` at converge. This repo owns the CONTENT; the role owns all
deployment machinery (systemd, cron fleet, watchdog, config.yaml, secrets).

## Layout

| Path                               | Role                                                                         |
| ---------------------------------- | ---------------------------------------------------------------------------- |
| `data/skills/dryvist/<skill>/`     | Hermes-specific skills (SKILL.md + scripts + tests)                          |
| `data/shared-skills-allowlist.nix` | Empty-by-design gate for workstation skills (human review per entry)         |
| `lib/bundle.nix`                   | Composes SOUL from the pinned `ai-llm-prompts` base and Hermes prompt bodies |
| `checks/validate-skills.nix`       | Frontmatter + SOUL sentinel contract check                                   |

## Rules

- SOUL.md prompts are NEVER vendored here. They are read from the immutable
  `ai-llm-prompts` input and have OKF frontmatter stripped at build time.
  This repository continues to own Hermes skills only.
- Skill frontmatter must keep `name:`, `description:`, `version:` (the check
  fails the flake otherwise) and the `metadata.hermes` block Hermes uses.
- Consumers pin release tags. Content changes here reach the agent only after
  a release + a pin bump in ansible-proxmox-apps.
- Git-flow: default branch `develop`; merges to `main` release via
  release-please.

## Hermes runtime behavior (non-obvious)

- **Memory is a frozen snapshot.** Changes made during a session (kanban,
  memory writes) do not appear in the system prompt until the *next* session
  starts. `MEMORY.md` is bounded (~2,200 chars); the agent consolidates it
  when full.
- **Cron jobs run in a fresh session** with no memory of prior runs. The
  prompt must be fully self-contained. Temporal filtering ("past 24 hours")
  is the official guide's only anti-repetition answer and is not sufficient
  for a recurring report that must never repeat itself — such a job must
  explicitly recall a named memory key at start and save updated state at end.
- **Kanban is for discrete tasks; cron is for repetitive scheduled work.** A
  recurring job on the kanban board accumulates cards indefinitely.
- **Kanban idempotency-key trap**: `hermes kanban create --idempotency-key`
  dedups against `status != 'archived'`. `hermes kanban complete` sets status
  to `done`, not `archived` — there is no auto-archive and no `--archive`
  flag. A stable key therefore matches the completed row forever (job runs
  once, then silently stops); a key that varies per fire accumulates cards
  unbounded. Neither is safe without explicit archiving.
- `hermes cron create` has no kanban action — payload is a prompt (LLM run)
  or `--script <path under ~/.hermes/scripts/>` (with `--no-agent` the
  script's stdout IS the delivered output).
- Prompt-cache stability is a real cost lever: an explicit `/model` switch,
  provider fallback, or credential rotation forces a full re-read at full
  price.
- Security: never set `GATEWAY_ALLOW_ALL_USERS=true` on a bot with terminal
  access — use platform allowlists or DM pairing. A container backend skips
  dangerous-command checks; the container is the security boundary instead.
- Anything not covered here: <https://hermes-agent.nousresearch.com/docs/guides/tips>.

## Verification

```sh
nix flake check
nix build .#hermes-bundle && find result -type f
```
