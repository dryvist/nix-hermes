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

  # INVERTED 2026-08-02, and the inversion is the point. This gate used to
  # assert the persona states NO spend figure, on the premise that the router
  # enforced the cap. It does not: the LiteLLM proxy is deliberately
  # storage-less, spend metering needs a shared store it lacks, and one shared
  # credential serves every caller so there is nothing to meter per caller.
  #
  # With no enforcement anywhere, a figure in the persona is not redundant
  # prose — it is the ONLY control that exists, because the agent is the only
  # thing that can apply it. The old gate was therefore failing the build to
  # protect a claim that was false, and deleting the figure left the unattended
  # agent with no cap at all while telling it one was in force.
  #
  # So: require the figure, and require it to be marked self-enforced. If a
  # deployment ever does enforce spend, this assertion is what must be
  # revisited first.
  grep -qE '\$[0-9]+(\.[0-9]+)?/day' ${bundle}/SOUL.md \
    || { echo "SOUL.md states no spend cap; nothing else enforces one"; fail=1; }
  grep -q 'YOU enforce' ${bundle}/SOUL.md \
    || { echo "SOUL.md's spend cap is not marked self-enforced"; fail=1; }

  [ "$fail" -eq 0 ] || exit 1
  touch $out
''
