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

## Verification

```sh
nix flake check
nix build .#hermes-bundle && find result -type f
```
