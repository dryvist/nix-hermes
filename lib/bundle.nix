# The hermes-bundle derivation: everything the Ansible hermes_agent role
# copies verbatim into $HERMES_HOME. Layout:
#   result/skills/dryvist/<skill>/...   agent skills (SKILL.md + scripts/tests)
#   result/SOUL.md                      persona: shared base + Hermes variant
#
# SOUL.md is composed fresh from the pinned ai-llm-prompts catalog's
# autonomous-base.md plus the canonical Hermes surface. OKF frontmatter is
# stripped before delivery; prompt ownership never drifts back into this repo.
#
# Skills come from two places. Most are authored here under data/skills. Skills
# every harness needs — identical behavior for this agent and for the
# workstation CLIs — are authored once in ai-assistant-instructions and enter
# through data/shared-skills-allowlist.nix, which carries the human safety
# review each one required.
{
  pkgs,
  ai-llm-prompts,
  ai-assistant-instructions,
}:

let
  inherit (pkgs) lib;

  # Resolves an allowlist entry's `input` name to its store path. A new source
  # input must be added here and to the function arguments, so an entry can
  # never name an input this derivation does not actually receive.
  sharedSkillInputs = {
    inherit ai-assistant-instructions;
  };

  allowlist = import ../data/shared-skills-allowlist.nix;

  copyShared = lib.concatMapStrings (entry: ''
    if [ -e "$out/skills/${entry.target}" ]; then
      echo "shared skill '${entry.target}' collides with a local data/skills copy;" >&2
      echo "delete the local copy in the same change — ending the duplication is the point" >&2
      exit 1
    fi
    mkdir -p "$out/skills/${entry.target}"
    cp -R ${sharedSkillInputs.${entry.input}}/${entry.skill}/. "$out/skills/${entry.target}/"
  '') allowlist;
in

pkgs.runCommand "hermes-bundle" { } ''
  mkdir -p $out/skills
  cp -R ${../data/skills}/. $out/skills/
  # Copies from the store arrive read-only, which would block writing shared
  # skills into the same tree.
  chmod -R u+w $out/skills

  ${copyShared}

  # SOUL.md = provenance comment + the two catalog bodies. Each OKF document
  # begins with YAML frontmatter bounded by `---`; sed removes only that first
  # block and passes the model-directed body byte-for-byte thereafter.
  {
    printf '<!-- managed by nix-hermes (lib/bundle.nix); sources: %s -->\n' \
      "ai-llm-prompts auto-ai-agent/autonomous-base.md + auto-ai-agent/hermes.md"
    sed '1,/^---$/d' \
      ${ai-llm-prompts}/auto-ai-agent/autonomous-base.md
    printf '\n'
    sed '1,/^---$/d' \
      ${ai-llm-prompts}/auto-ai-agent/hermes.md
  } > $out/SOUL.md

  # The base block must have been extracted (guards an upstream fence rename).
  grep -q 'autonomous engineering agent' $out/SOUL.md
  grep -q '^## You are Hermes' $out/SOUL.md
  ! grep -q '^type: LLM Prompt' $out/SOUL.md
''
