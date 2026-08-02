# Bundle contract check: every shipped skill carries the frontmatter Hermes'
# skill loader needs, every allowlisted shared skill actually arrived, and
# SOUL.md really is base + Hermes variant.
{ pkgs, bundle }:

let
  inherit (pkgs) lib;
  allowlist = import ../data/shared-skills-allowlist.nix;

  # A shared skill that silently fails to copy would leave the agent with no
  # skill at all — worse than the duplicate it replaced, and invisible, since
  # the loop above only checks whatever happens to be present.
  assertShared = lib.concatMapStrings (entry: ''
    [ -f "${bundle}/skills/${entry.target}/SKILL.md" ] || {
      echo "allowlisted shared skill missing from bundle: ${entry.target}"; fail=1; }
  '') allowlist;
in

pkgs.runCommand "validate-skills" { } ''
  fail=0

  skills=$(find ${bundle}/skills/dryvist -mindepth 1 -maxdepth 1 -type d)
  [ -n "$skills" ] || { echo "no skills in bundle"; exit 1; }

  for d in $skills; do
    s="$d/SKILL.md"
    [ -f "$s" ] || { echo "missing SKILL.md: $d"; fail=1; continue; }
    for field in name description version; do
      grep -q "^$field:" "$s" || { echo "missing frontmatter '$field': $s"; fail=1; }
    done
  done

  ${assertShared}

  # SOUL sentinels: the shared base block and the Hermes surface variant.
  grep -q 'autonomous engineering agent' ${bundle}/SOUL.md || { echo "SOUL.md missing base"; fail=1; }
  grep -q '^## You are Hermes' ${bundle}/SOUL.md || { echo "SOUL.md missing Hermes variant"; fail=1; }
  grep -q '^Tools:$' ${bundle}/SOUL.md || { echo "SOUL.md missing Hermes tools"; fail=1; }
  grep -q '^Escalation routing:$' ${bundle}/SOUL.md || { echo "SOUL.md missing escalation routing"; fail=1; }
  grep -q '^Model fabric:' ${bundle}/SOUL.md || { echo "SOUL.md missing model fabric"; fail=1; }
  ! grep -q '^type: LLM Prompt' ${bundle}/SOUL.md || { echo "SOUL.md leaked OKF frontmatter"; fail=1; }

  # Delegation doctrine sentinels. These exist because a stale ai-llm-prompts
  # pin fails silently: the build succeeds and ships a persona missing the
  # doctrine while still carrying the prose spend figure it replaced. Nothing
  # else in this check inspects SOUL.md content closely enough to notice.
  grep -q 'Delegate bounded work to the shared router' ${bundle}/SOUL.md \
    || { echo "SOUL.md missing delegation doctrine (stale ai-llm-prompts pin?)"; fail=1; }

  # Spend caps are enforced by the router against this agent's key. A figure
  # written into the persona is prose the agent cannot enforce and that drifts
  # from router config the moment the cap moves.
  ! grep -qE '\$[0-9]+(\.[0-9]+)?\s*(/|per )\s*day' ${bundle}/SOUL.md \
    || { echo "SOUL.md states a spend figure; budgets are router-enforced"; fail=1; }

  [ "$fail" -eq 0 ] || exit 1
  touch $out
''
