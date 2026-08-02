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
    # UNMERGED branch revision — repin to merged main before this lands.
    #
    # MERGE ORDER (load-bearing in both directions, do not reorder):
    #   1. ai-llm-prompts       PR #26  -> its main (trunk-flow repo)
    #   2. claude-code-plugins  PR #450 -> its main (trunk-flow repo)
    #   3. repin BOTH inputs here to those merged revisions
    #   4. this PR lands
    # checks/validate-skills.nix asserts content that only exists at or after
    # step 1, so landing this first fails the build rather than shipping
    # quietly. That is the gate working, not a coupling to route around.
    #
    # Neither older pin is a safe fallback, for OPPOSITE reasons — do not
    # "roll back" to either without reading both:
    #   7b427bbf (pre-doctrine) carries the honest self-enforced spend figure
    #     but none of the delegation doctrine.
    #   f087d04  carries the doctrine but DELETED that figure, on the since-
    #     disproven premise that the router enforced the cap. It does not, so
    #     that revision leaves an unattended agent with no spend control at all
    #     while telling it one is in force. The sentinel rejects it by design.
    ai-llm-prompts = {
      url = "github:dryvist/ai-llm-prompts/d7a4a20";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Owner of cross-harness skills — the ones whose behavior must be identical
    # here and on the workstation CLIs. This is the plugin marketplace, and it
    # owns every skill in the estate that is not authored in data/skills here;
    # ai-assistant-instructions deliberately ships configuration only, so a
    # skill may not live there. Consumed only through
    # data/shared-skills-allowlist.nix, never wholesale. Not a flake.
    #
    # The marketplace layout is Claude Code's, but the two skills taken from it
    # are not: they use only shell, curl, and jq, name no model id, and read
    # their endpoint from the environment. Nothing in them assumes a Claude
    # session, which is what makes one authored copy serve both harnesses.
    #
    # UNMERGED branch revision — repin to merged main before this lands.
    # Step 2 of the merge order stated at ai-llm-prompts above; both inputs are
    # unmerged, so neither may keep a branch pin at merge time. A green build
    # proves nothing about WHICH revision it built against — that is precisely
    # how a stale pin shipped a persona missing its doctrine earlier in this
    # branch, which is why validate-skills now asserts content, not just shape.
    claude-code-plugins = {
      url = "github:dryvist/claude-code-plugins/786e1f1";
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
            inherit (inputs) ai-llm-prompts claude-code-plugins;
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
