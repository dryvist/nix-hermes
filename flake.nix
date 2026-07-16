{
  description = "Shared content bundle (skills + SOUL persona) for the Hermes autonomous agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    dryvist-github = {
      url = "github:dryvist/.github";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Source of truth for the shared autonomous base prompt. The bundle
    # composes SOUL.md from its agentsmd/prompts/autonomous-base.md fenced
    # base block plus the Hermes surface variant in data/soul/ — replacing
    # the vendored (drift-prone) copy the Ansible role used to carry.
    ai-assistant-instructions = {
      url = "github:dryvist/ai-assistant-instructions";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        inputs.dryvist-github.flakeModules.dev-hygiene
      ];

      perSystem =
        { pkgs, ... }:
        let
          bundle = import ./lib/bundle.nix {
            inherit pkgs;
            inherit (inputs) ai-assistant-instructions;
          };
        in
        {
          # data/ is verbatim agent content (skills + SOUL variant) consumed
          # byte-for-byte by the hermes_agent Ansible role — formatters and
          # markdown lint must never rewrite it (prompt fragments legitimately
          # violate MD041 etc.).
          treefmt.settings.global.excludes = [ "data/**" ];
          pre-commit.settings.hooks.markdownlint-cli2.excludes = [ "^data/" ];
          # The docs-pr redaction unit test contains a FAKE inline PEM marker
          # string to assert secrets get scrubbed — not a real key.
          pre-commit.settings.hooks.detect-private-keys.excludes = [
            "^data/skills/dryvist/docs-pr/tests/test_open_signed_pr\\.py$"
          ];

          packages = {
            hermes-bundle = bundle;
            default = bundle;
          };

          checks.validate-skills = import ./checks/validate-skills.nix {
            inherit pkgs bundle;
          };
        };
    };
}
