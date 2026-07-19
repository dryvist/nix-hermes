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
frontmatter before delivery. Skills remain owned under `data/skills/dryvist/`.

## Sharing workstation skills

`data/shared-skills-allowlist.nix` is the explicit, human-reviewed gate for
pulling workstation skills into the bundle. It ships empty: Hermes runs
unattended with standing credentials, so each skill is reviewed before entry.

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
