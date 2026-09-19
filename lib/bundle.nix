# The agent bundle derivation: everything the Ansible hermes_agent role copies
# verbatim into $HERMES_HOME. Layout:
#   result/skills/dryvist/<skill>/...   agent skills (SKILL.md + scripts/tests)
#   result/SOUL.md                      persona + always-on behavioral rules
#   result/rules/on-demand/...          rule tier read by path, not delivered
#
# SOUL.md is composed fresh from the pinned ai-llm-prompts catalog's
# autonomous-base.md and the named agent's surface, followed by the four
# always-on agentsmd rules from the pinned ai-assistant-instructions input
# (AGENTS.md, soul.md, operating-core.md, public-disclosure.md — the same set
# every Nix-managed workstation harness already loads every session). OKF
# frontmatter is stripped before delivery; prompt/rule ownership never drifts
# back into this repo.
#
# Skills come from two places. Most are authored here under data/skills. Skills
# every harness needs — identical behavior for this agent and for the
# workstation CLIs — are authored once in the claude-code-plugins marketplace
# and enter through data/shared-skills-allowlist.nix, which carries the human
# safety review each one required.
{
  pkgs,
  ai-llm-prompts,
  browser-use,
  claude-code-plugins,
  ai-assistant-instructions,
  # Which persona this bundle carries. The value is BOTH the catalog fragment
  # basename (auto-ai-agent/<agent>.md) and the derivation name prefix, so a
  # bundle can never be named for one agent and filled with another's persona.
  #
  # Every agent gets the SAME skill set today. That is deliberate rather than
  # settled: the skills here are homelab operational tooling, and narrowing them
  # per agent is a change to make when a second agent's job is actually defined,
  # not one to guess at now.
  agent ? "hermes",
}:

let
  inherit (pkgs) lib;

  # The catalog writes headings in prose case ("## You are Hermes"), so the
  # guard below needs the capitalized form. Derived rather than passed as a
  # second argument: two independent strings could disagree, and the failure
  # would be a bundle whose guard silently matches nothing.
  agentName = lib.toUpper (lib.substring 0 1 agent) + lib.substring 1 (lib.stringLength agent) agent;

  # Resolves an allowlist entry's `input` name to its store path. A new source
  # input must be added here and to the function arguments, so an entry can
  # never name an input this derivation does not actually receive.
  sharedSkillInputs = {
    inherit browser-use claude-code-plugins;
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

pkgs.runCommand "${agent}-bundle" { } ''
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
      "ai-llm-prompts auto-ai-agent/autonomous-base.md + auto-ai-agent/${agent}.md"
    sed '1,/^---$/d' \
      ${ai-llm-prompts}/auto-ai-agent/autonomous-base.md
    printf '\n'
    sed '1,/^---$/d' \
      ${ai-llm-prompts}/auto-ai-agent/${agent}.md
    printf '\n'
    # The four always-on agentsmd rules every workstation harness already
    # follows (ai-assistant-instructions/agentsmd/rules/rule-tiers.md: "AGENTS.md,
    # soul.md, operating-core.md, and public-disclosure.md load every session").
    # AGENTS.md carries no OKF frontmatter; the three agentsmd/rules/*.md files
    # do, stripped the same way as the persona bodies above.
    printf '<!-- managed by nix-hermes (lib/bundle.nix); source: ai-assistant-instructions AGENTS.md -->\n'
    cat ${ai-assistant-instructions}/AGENTS.md
    printf '\n'
    for rule in soul operating-core public-disclosure; do
      printf '<!-- managed by nix-hermes (lib/bundle.nix); source: ai-assistant-instructions agentsmd/rules/%s.md -->\n' "$rule"
      sed '1,/^---$/d' "${ai-assistant-instructions}/agentsmd/rules/$rule.md"
      printf '\n'
    done
  } > $out/SOUL.md

  # The on-demand tier is read by path when an activity calls for it, never
  # delivered wholesale into SOUL.md — same load-on-demand contract described
  # in rule-tiers.md and already followed by every Nix-managed workstation.
  mkdir -p $out/rules/on-demand
  cp -R ${ai-assistant-instructions}/agentsmd/rules/on-demand/. $out/rules/on-demand/

  # The base block must have been extracted (guards an upstream fence rename).
  grep -q 'autonomous engineering agent' $out/SOUL.md
  grep -q '^## You are ${agentName}' $out/SOUL.md
  ! grep -q '^type: LLM Prompt' $out/SOUL.md

  # One sentinel per always-on rule — proves each body actually arrived and
  # was not truncated by a frontmatter-stripping regression, the same
  # protection the persona sentinels above give the catalog bodies.
  grep -qF 'YOU ARE the autonomous orchestrator' $out/SOUL.md
  grep -qF 'You are an autonomous orchestrator. You own a task through completion' $out/SOUL.md
  grep -qF 'Loaded every session. It holds only what changes behavior on every task' $out/SOUL.md
  grep -qF 'Everything in a public, git-committed artifact is published forever' $out/SOUL.md
''
