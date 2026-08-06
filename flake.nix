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
    # MERGE ORDER (load-bearing in both directions, do not reorder):
    #   1. ai-llm-prompts       PR #26  -> its main  [DONE, pinned below]
    #   2. claude-code-plugins  PR #450 -> its main (trunk-flow repo)
    #   3. repin claude-code-plugins here to that merged revision
    #   4. this PR lands
    # checks/validate-skills.nix asserts content that only exists at or after
    # step 1, so landing this first fails the build rather than shipping
    # quietly. That is the gate working, not a coupling to route around.
    #
    # Pinned at main's tip: 18e70c0 is the release commit sitting on c9bf665,
    # the squash of PR #26. The branch revision this input carried until now
    # (d7a4a20) is NOT an ancestor of main — a squash merge rewrites the commit,
    # so the pre-merge sha survives only as long as the branch does and names
    # nothing on the repo's history line once it is deleted. Verified before
    # repinning that all three sentinel strings survive the squash; a squash can
    # silently drop content, and only a re-probe proves it did not.
    #
    # No older pin is a safe fallback, and the two nearest are unsafe for
    # OPPOSITE reasons — do not "roll back" to either without reading both:
    #   7b427bbf (pre-doctrine) carries the honest self-enforced spend figure
    #     but none of the delegation doctrine.
    #   f087d04  carries the doctrine but DELETED that figure, on the since-
    #     disproven premise that the router enforced the cap. It does not, so
    #     that revision leaves an unattended agent with no spend control at all
    #     while telling it one is in force. The sentinel rejects it by design.
    #   d8caf8c  adds auto-ai-agent/donna.md, the second agent's surface. It
    #     leaves autonomous-base.md and hermes.md byte-identical to ed8e4b4, so
    #     this bump does not change what hermes-bundle SHIPS. Verified by
    #     rebuilding at both pins and diffing the outputs: `diff -r` reports no
    #     difference and SOUL.md hashes to c4b725cd either way.
    #
    #     Compare CONTENT, not the store path. These derivations are
    #     input-addressed, so bumping this rev moves hermes-bundle's path even
    #     when every shipped byte is the same — a path change here is expected
    #     and proves nothing on its own, in either direction.
    ai-llm-prompts = {
      url = "github:dryvist/ai-llm-prompts/d8caf8ca3dc4ef224a160fd6b6a2fd3b93ee01fd";
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
    # UNMERGED branch revision — the last one left, and step 2 of the merge
    # order stated at ai-llm-prompts above. It may not keep a branch pin at
    # merge time: PR #450 targets main and will be squashed, so this sha stops
    # naming anything on that repo's history line the moment the branch is
    # deleted. A green build proves nothing about WHICH revision it built
    # against — that is precisely how a stale pin shipped a persona missing its
    # doctrine earlier in this branch, which is why validate-skills now asserts
    # content, not just shape.
    claude-code-plugins = {
      url = "github:dryvist/claude-code-plugins/fe173de";
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
              inherit (inputs) ai-llm-prompts claude-code-plugins;
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
          # The docs-pr redaction unit test contains a FAKE inline PEM marker
          # string to assert secrets get scrubbed — not a real key.
          pre-commit.settings.hooks.detect-private-keys.excludes = [
            "^data/skills/dryvist/docs-pr/tests/test_open_signed_pr\\.py$"
          ];

          packages = {
            hermes-bundle = bundle;
            donna-bundle = donnaBundle;
            default = bundle;
          };

          checks = {
            validate-skills = import ./checks/validate-skills.nix {
              inherit pkgs bundle;
            };

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
            # which is the exact failure mode the pin comments above exist to
            # prevent for Hermes.
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
