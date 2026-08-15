# Changelog

## [0.14.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.13.0...nix-hermes-v0.14.0) (2026-08-15)


### Features

* **skills:** adopt github-code-search into the Hermes bundle ([#68](https://github.com/dryvist/nix-hermes/issues/68)) ([f1bb65d](https://github.com/dryvist/nix-hermes/commit/f1bb65d23a9d97398293d2ccea18ef5514f31afc))

## [0.13.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.12.0...nix-hermes-v0.13.0) (2026-08-13)


### Features

* bundle Browser Use skill for Hermes ([#63](https://github.com/dryvist/nix-hermes/issues/63)) ([8fab163](https://github.com/dryvist/nix-hermes/commit/8fab163625cc12ec1787bdfda17230fbe018ab95))


### Bug Fixes

* **renovate:** track flake inputs pinned to an explicit revision ([#61](https://github.com/dryvist/nix-hermes/issues/61)) ([f4c04b5](https://github.com/dryvist/nix-hermes/commit/f4c04b51b69213ee595bbff3c608e9425455ee47))

## [0.12.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.11.0...nix-hermes-v0.12.0) (2026-08-06)


### Features

* **bundle:** build a bundle per agent, and add donna-bundle ([#54](https://github.com/dryvist/nix-hermes/issues/54)) ([0f64c92](https://github.com/dryvist/nix-hermes/commit/0f64c92d29becb65328091f315c2bdaccd3ffa26))

## [0.11.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.10.0...nix-hermes-v0.11.0) (2026-08-05)


### Features

* **ci:** relock the whole flake into a single pull request ([#50](https://github.com/dryvist/nix-hermes/issues/50)) ([255bc19](https://github.com/dryvist/nix-hermes/commit/255bc19a535196c0d81e585b07c0e6934e1e12a1))

## [0.10.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.9.0...nix-hermes-v0.10.0) (2026-08-05)


### Features

* repin ai-llm-prompts to pick up the Hermes output contract ([#46](https://github.com/dryvist/nix-hermes/issues/46)) ([c01d118](https://github.com/dryvist/nix-hermes/commit/c01d118507d8da71fcf065cb03e27079839ad4ec))

## [0.9.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.8.0...nix-hermes-v0.9.0) (2026-08-02)


### Features

* **skills:** add docs-starlight-authoring skill ([#38](https://github.com/dryvist/nix-hermes/issues/38)) ([e5e6ccc](https://github.com/dryvist/nix-hermes/commit/e5e6cccde156acc69777b531556b772f997e5ef9))

## [0.8.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.7.0...nix-hermes-v0.8.0) (2026-07-30)


### Features

* **ci:** refresh nixpkgs channel pin on a schedule ([#33](https://github.com/dryvist/nix-hermes/issues/33)) ([bee0ced](https://github.com/dryvist/nix-hermes/commit/bee0cedfcb35aa0c14a82964c64ee034a5aa664d))

## [0.7.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.6.0...nix-hermes-v0.7.0) (2026-07-28)


### Features

* **skills:** add hardware/disk-failure lens to splunk-monitor ([#29](https://github.com/dryvist/nix-hermes/issues/29)) ([f0bfb44](https://github.com/dryvist/nix-hermes/commit/f0bfb44fc09ae848441aade064eee4a4ef923c1e))

## [0.6.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.5.1...nix-hermes-v0.6.0) (2026-07-19)


### Features

* consume central Hermes prompts (commit-pinned ai-llm-prompts input) ([#25](https://github.com/dryvist/nix-hermes/issues/25)) ([c9f9a67](https://github.com/dryvist/nix-hermes/commit/c9f9a679fb897e872efdc338b90f132618dcc401))

## [0.5.1](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.5.0...nix-hermes-v0.5.1) (2026-07-19)


### Bug Fixes

* **soul:** sync hermes-variant with the canonical ai-llm-prompts surface ([#22](https://github.com/dryvist/nix-hermes/issues/22)) ([a0deff6](https://github.com/dryvist/nix-hermes/commit/a0deff6b672af16b5ea6f1daf08924a108544357))

## [0.5.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.4.0...nix-hermes-v0.5.0) (2026-07-19)


### Features

* **skills:** openrouter-models — discovery, budgeted escalation, request lane ([#19](https://github.com/dryvist/nix-hermes/issues/19)) ([8de5c7f](https://github.com/dryvist/nix-hermes/commit/8de5c7f1c6feebf300722fe5ea70b26a9b4c87bb))

## [0.4.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.3.0...nix-hermes-v0.4.0) (2026-07-16)


### Features

* **soul:** declare router model-fabric access incl. OpenRouter aliases ([#13](https://github.com/dryvist/nix-hermes/issues/13)) ([1dbcc57](https://github.com/dryvist/nix-hermes/commit/1dbcc57785eeb823fcf44635404426291a1cc05c))

## [0.3.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.2.0...nix-hermes-v0.3.0) (2026-07-16)


### Features

* **skills:** harden zammad-incidents dedup, severity map, auto-close ([#6](https://github.com/dryvist/nix-hermes/issues/6)) ([be90c11](https://github.com/dryvist/nix-hermes/commit/be90c111f6135586ef2f5c5dae7f2094fdfeb6b7))


### Bug Fixes

* **skills:** splunk-monitor must never pass an app parameter ([#5](https://github.com/dryvist/nix-hermes/issues/5)) ([3e51f26](https://github.com/dryvist/nix-hermes/commit/3e51f2628d27826b387cec6bc936c798c1f0967e))

## [0.2.0](https://github.com/dryvist/nix-hermes/compare/nix-hermes-v0.1.0...nix-hermes-v0.2.0) (2026-07-16)


### Features

* hermes-bundle flake — skills + composed SOUL persona ([f381837](https://github.com/dryvist/nix-hermes/commit/f3818375c385095fb8cca21e47bbd99b2bfeba41))


### Bug Fixes

* **ci:** pass the org release App key to the reusable release-please workflow ([945fa1e](https://github.com/dryvist/nix-hermes/commit/945fa1e194a976f7df16bd004ddd56d558d86bb6))
