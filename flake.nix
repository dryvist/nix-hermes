{
  description = "Shared content bundle (skills + SOUL persona) for the Hermes autonomous agent";

  inputs = {
    # Channel branch = intended pin (unstable). Renovate CANNOT bump this: it
    # updates an input when its ref changes, and a channel branch's ref never
    # changes. deps-flake-lock.yml relocks the whole file on a schedule.
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
    # Tracks the default branch. checks/validate-skills.nix asserts the SOUL
    # content this input must carry (shared base, Hermes surface, delegation
    # doctrine), so a relock to a revision that drops any of it fails the
    # build rather than shipping quietly.
    #
    # Compare CONTENT, not the store path. These derivations are
    # input-addressed, so a relock moves hermes-bundle's path even when every
    # shipped byte is the same — a path change proves nothing on its own.
    ai-llm-prompts = {
      url = "github:dryvist/ai-llm-prompts";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Owner of cross-harness skills — the ones whose behavior must be identical
    # here and on the workstation CLIs. This is the plugin marketplace, and it
    # owns every skill in the estate that is not authored in data/skills here;
    # ai-assistant-instructions deliberately ships configuration only, so a
    # skill may not live there. Consumed only through
    # data/shared-skills-allowlist.nix, never wholesale. Not a flake.
    #
    # The marketplace layout is Claude Code's, but each allowlisted skill is
    # reviewed for cross-harness use and copied unchanged into this bundle.
    #
    # Tracks the default branch. checks/validate-skills.nix asserts that every
    # skill in data/shared-skills-allowlist.nix arrives with the frontmatter
    # the loader needs (`version` included), so a relock to a revision that
    # lacks it fails the build rather than shipping quietly.
    claude-code-plugins = {
      url = "github:dryvist/claude-code-plugins";
      flake = false;
    };

    # Owner of the shared agentsmd rules — the always-on behavioral contract
    # every workstation harness already follows (Claude/Codex/Gemini via
    # AGENTS.md/CLAUDE.md/GEMINI.md symlinks). Hermes runs unattended and
    # today follows none of it; lib/bundle.nix appends the same four
    # always-on files (per that repo's own `agentsmd/rules/rule-tiers.md`)
    # to SOUL.md and ships the on-demand tier alongside it, so this agent
    # reads the identical rule set from the identical single source.
    #
    # Tracks the default branch (develop).
    ai-assistant-instructions = {
      url = "github:dryvist/ai-assistant-instructions";
      flake = false;
    };

    # Official Browser Use skill source. The bundle takes only its reviewed
    # CLI skill, byte-for-byte, through data/shared-skills-allowlist.nix.
    browser-use = {
      url = "github:browser-use/browser-use";
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
          # One derivation per agent, differing only in which catalog surface
          # is appended to the shared base. The skills are identical, so the
          # two bundles share every input but that one fragment.
          mkBundle =
            agent:
            import ./lib/bundle.nix {
              inherit pkgs agent;
              inherit (inputs)
                ai-llm-prompts
                browser-use
                claude-code-plugins
                ai-assistant-instructions
                ;
            };

          # Still named `bundle` because the skills check below consumes it, and
          # what that check validates — skill frontmatter and the Hermes SOUL
          # sentinels — is either identical across bundles or Hermes-specific.
          bundle = mkBundle "hermes";

          # Bound rather than written inline under `packages` because it has to
          # appear in BOTH packages and checks. The checks entry is the
          # load-bearing one; see there for why.
          donnaBundle = mkBundle "donna";
        in
        {
          # data/ is verbatim agent content (skills + SOUL variant) consumed
          # byte-for-byte by the hermes_agent Ansible role — formatters and
          # markdown lint must never rewrite it (prompt fragments legitimately
          # violate MD041 etc.).
          treefmt.settings.global.excludes = [ "data/**" ];
          pre-commit.settings.hooks.markdownlint-cli2.excludes = [ "^data/" ];

          packages = {
            hermes-bundle = bundle;
            donna-bundle = donnaBundle;
            default = bundle;
          };

          checks = {
            validate-skills = import ./checks/validate-skills.nix {
              inherit pkgs bundle;
            };

            validate-new-skills = import ./checks/validate-new-skills.nix {
              inherit pkgs bundle;
            };

            # Every skill's tests/test_*.py, run against the source tree.
            skill-tests = pkgs.runCommand "skill-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              for d in ${./data/skills/dryvist}/*/tests; do
                (cd "$d" && python3 -m unittest discover -s . -p 'test_*.py') || exit 1
              done
              touch $out
            '';

            # Listed as a CHECK, not merely a package, because `nix flake
            # check` EVALUATES packages without building them — it prints
            # "build skipped" and passes. Confirmed against a probe flake whose
            # package builder was `exit 1`: flake check reported it green.
            #
            # That distinction is the whole point here. Everything proving this
            # bundle is correct — the shared base block arrived, the Donna
            # surface arrived, no OKF frontmatter leaked — is asserted inside
            # the derivation's builder (lib/bundle.nix), so a package that is
            # never built asserts nothing while still showing a green check.
            # A stale or renamed ai-llm-prompts fragment would ship silently,
            # which is the exact failure mode validate-skills prevents for
            # Hermes.
            #
            # hermes-bundle needs no equivalent line only because
            # validate-skills takes it as an input, and that dependency is what
            # forces its build. Delete that check and Hermes loses this
            # protection too — the coverage is a side effect, not a decision.
            donna-bundle = donnaBundle;
          };
        };
    };
}
