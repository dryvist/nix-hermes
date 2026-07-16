# The hermes-bundle derivation: everything the Ansible hermes_agent role
# copies verbatim into $HERMES_HOME. Layout:
#   result/skills/dryvist/<skill>/...   agent skills (SKILL.md + scripts/tests)
#   result/SOUL.md                      persona: shared base + Hermes variant
#
# SOUL.md is composed fresh from the ai-assistant-instructions input's
# autonomous-base.md (the ```text fenced base block) plus the Hermes surface
# delta in data/soul/hermes-variant.md — the base is never vendored, so it
# cannot drift from the source of truth again.
#
# Shared workstation skills (nix-ai / claude plugin ecosystem) are NOT copied
# here yet: data/shared-skills-allowlist.nix documents the mechanism, and each
# skill enters only after a human safety review (an unattended autonomous
# agent is not a workstation assistant).
{ pkgs, ai-assistant-instructions }:

pkgs.runCommand "hermes-bundle" { } ''
  mkdir -p $out/skills
  cp -R ${../data/skills}/. $out/skills/

  # SOUL.md = provenance comment + the fenced base block + the Hermes variant.
  {
    printf '<!-- managed by nix-hermes (lib/bundle.nix); sources: %s -->\n' \
      "ai-assistant-instructions agentsmd/prompts/autonomous-base.md + data/soul/hermes-variant.md"
    awk '/^```text$/{f=1;next} /^```$/{f=0} f' \
      ${ai-assistant-instructions}/agentsmd/prompts/autonomous-base.md
    printf '\n'
    cat ${../data/soul/hermes-variant.md}
  } > $out/SOUL.md

  # The base block must have been extracted (guards an upstream fence rename).
  grep -q 'autonomous engineering agent' $out/SOUL.md
''
