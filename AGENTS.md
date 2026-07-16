# nix-hermes — AI Agent Documentation

Builds `packages.<system>.hermes-bundle`: the static content tree (skills +
SOUL.md) the `hermes_agent` Ansible role (ansible-proxmox-apps) copies into
`$HERMES_HOME` at converge. This repo owns the CONTENT; the role owns all
deployment machinery (systemd, cron fleet, watchdog, config.yaml, secrets).

## Layout

| Path                               | Role                                                                           |
| ---------------------------------- | ------------------------------------------------------------------------------ |
| `data/skills/dryvist/<skill>/`     | Hermes-specific skills (SKILL.md + scripts + tests)                            |
| `data/soul/hermes-variant.md`      | Hermes surface delta appended to the shared base prompt                        |
| `data/shared-skills-allowlist.nix` | Empty-by-design gate for workstation skills (human review per entry)           |
| `lib/bundle.nix`                   | Composes the bundle; extracts the base prompt from `ai-assistant-instructions` |
| `checks/validate-skills.nix`       | Frontmatter + SOUL sentinel contract check                                     |

## Rules

- SOUL.md's base block is NEVER vendored here — it is extracted at build time
  from the `ai-assistant-instructions` input (`agentsmd/prompts/autonomous-base.md`).
  Edit intent there; edit only the Hermes delta here.
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
