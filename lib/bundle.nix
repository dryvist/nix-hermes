# The hermes-bundle derivation: everything the Ansible hermes_agent role
# copies verbatim into $HERMES_HOME. Layout:
#   result/skills/dryvist/<skill>/...   agent skills (SKILL.md + scripts/tests)
#   result/SOUL.md                      persona: shared base + Hermes variant
#
# SOUL.md is composed fresh from the pinned ai-llm-prompts catalog's
# autonomous-base.md plus the canonical Hermes surface. OKF frontmatter is
# stripped before delivery; prompt ownership never drifts back into this repo.
#
# Shared workstation skills (nix-ai / claude plugin ecosystem) are NOT copied
# here yet: data/shared-skills-allowlist.nix documents the mechanism, and each
# skill enters only after a human safety review (an unattended autonomous
# agent is not a workstation assistant).
{ pkgs, ai-llm-prompts }:

pkgs.runCommand "hermes-bundle" { } ''
  mkdir -p $out/skills
  cp -R ${../data/skills}/. $out/skills/

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
