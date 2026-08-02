{
  description = "Shared content bundle (skills + SOUL persona) for the Hermes autonomous agent";

  inputs = {
    # Channel branch = intended pin (unstable). Renovate CANNOT bump this: it
    # updates an input when its ref changes, and a channel branch's ref never
    # changes. deps-refresh-nixpkgs.yml refreshes the lock on a schedule.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    dryvist-github = {
      url = "github:dryvist/.github";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Immutable source of truth for the shared autonomous base and Hermes
    # surface prompts. Repo-local skills stay owned by this repository.
    #
    # Unmerged branch revision — repin to merged main before this lands. The
    # old pin is NOT a safe fallback here: it predates the delegation doctrine
    # and still carries the self-tracked spend figure the persona cannot
    # enforce, so merging against it would ship the exact divergence this
    # change removes. See the repin note on ai-assistant-instructions below.
    ai-llm-prompts = {
      url = "github:dryvist/ai-llm-prompts/f087d0407615982bb44e5d1bc77c1b40434146d4";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Owner of cross-harness skills — the ones whose behavior must be identical
    # here and on the workstation CLIs. Consumed only through
    # data/shared-skills-allowlist.nix, never wholesale. Not a flake.
    #
    # Unmerged branch revision — repin to merged develop before this lands.
    # Both prompt/skill inputs above and here are unmerged: neither may keep a
    # branch pin at merge time, and a build that succeeds proves nothing about
    # which revision it built against.
    ai-assistant-instructions = {
      url = "github:dryvist/ai-assistant-instructions/282b858";
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
            inherit (inputs) ai-llm-prompts ai-assistant-instructions;
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
