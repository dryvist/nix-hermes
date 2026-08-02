# nix-hermes

Shared content bundle (skills + SOUL persona) for the Hermes autonomous agent,
built with Nix from the same sources the rest of the AI config ecosystem uses.

[![CI](https://github.com/dryvist/nix-hermes/actions/workflows/ci.yml/badge.svg)](https://github.com/dryvist/nix-hermes/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Installation

No installation. Consumers build the bundle straight from the flake:

```sh
nix build github:dryvist/nix-hermes#hermes-bundle
```

The result is a static tree an Ansible role (or anything else) copies verbatim
into the agent's home:

```text
result/
├── skills/dryvist/<skill>/   # SKILL.md + scripts/ + tests/ per skill
└── SOUL.md                   # persona: shared autonomous base + Hermes variant
```

## Usage

- `nix build .#hermes-bundle` — build the bundle locally.
- `nix flake check` — build + validate every skill's frontmatter and the
  SOUL.md composition sentinels.

`SOUL.md` is composed at build time from the shared autonomous base and Hermes
surface in the immutable `ai-llm-prompts` flake input. The bundle strips OKF
frontmatter before delivery. Most skills are owned under `data/skills/dryvist/`;
the rest arrive through the allowlist below.

## Sharing skills authored elsewhere

`data/shared-skills-allowlist.nix` is the explicit, human-reviewed gate for
pulling in a skill this repository does not author. Hermes runs unattended with
standing credentials, so each entry is reviewed before it enters and the review
is recorded in that file.

It currently carries `delegate-to-router` and `openrouter-models`, authored in
the `ai-delegation` plugin of the `claude-code-plugins` marketplace and pinned
as a non-flake input. Those two are shared rather than copied because their
behavior has to be identical here and on the workstation CLIs — they govern
spend and egress, and two copies would drift on exactly those rules while the
holder of the stale one had no way to notice.

Delivery is byte-for-byte, and `lib/bundle.nix` refuses an entry that would land
on a path `data/skills/` already occupies: adopting a shared skill means
deleting the local copy in the same change, which is the only reason to adopt
one. `checks/validate-skills.nix` then asserts each allowlisted skill actually
arrived, because a copy that silently failed would leave the agent with no skill
at all.

## Consumers

Anything that can run `nix build` and copy files. Consumers pin a release tag
(e.g. `github:dryvist/nix-hermes/v1.0.0#hermes-bundle`) and bump it
deliberately.

## Contributing

Conventional Commits; PRs target `develop` (git-flow). Every merge to `main`
releases via release-please.

## License

MIT — see [LICENSE](LICENSE).

---

More documentation: <https://docs.jacobpevans.com>
