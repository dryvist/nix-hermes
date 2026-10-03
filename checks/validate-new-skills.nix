# Contract check for the pr-review and repo-crawl skills: the frontmatter
# check in validate-skills.nix already covers every skill generically; this
# adds the behavioral sentinels specific to an unattended review/crawl agent
# (never APPROVE, never merge, dedupe marker, caps checked up front) plus
# repo-crawl's checklist.json schema and its detector's own test suite,
# kept in its own file/script so the shell logic lives in checks/, not
# inlined into the .nix expression.
{ pkgs, bundle }:

pkgs.runCommand "validate-new-skills"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.python3
    ];
  }
  ''
    bash ${./validate-new-skills.sh} ${bundle}
    touch $out
  ''
