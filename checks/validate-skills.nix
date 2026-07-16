# Bundle contract check: every shipped skill carries the frontmatter Hermes'
# skill loader needs, and SOUL.md really is base + Hermes variant.
{ pkgs, bundle }:

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

  # SOUL sentinels: the shared base block and the Hermes surface variant.
  grep -q 'autonomous engineering agent' ${bundle}/SOUL.md || { echo "SOUL.md missing base"; fail=1; }
  grep -q '^## You are Hermes' ${bundle}/SOUL.md || { echo "SOUL.md missing Hermes variant"; fail=1; }

  [ "$fail" -eq 0 ] || exit 1
  touch $out
''
