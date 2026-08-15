# Allowlist for sharing skills authored OUTSIDE this repository into the
# Hermes bundle. Hermes runs unattended with standing credentials, so every
# shared skill needs a human safety review before it enters — a workstation
# skill's assumptions (interactive user, reversible actions, no autonomous
# cron context) do not transfer for free.
#
# Entry shape:
#   { input  = "<flake input holding the skill>";
#     skill  = "<directory path within that input>";
#     target = "<path under the bundle's skills/ root>"; }
#
# `target` is explicit rather than derived so a skill's delivered path can be
# held stable while its upstream location moves. That matters here: the Hermes
# persona names `dryvist/openrouter-models`, so the delivered path must keep
# that spelling even though the source directory is not namespaced.
#
# lib/bundle.nix copies each entry after the local data/skills tree and fails
# if an entry would land on a path that tree already occupies — adopting a
# shared skill therefore requires deleting the local copy in the same change,
# which is the point: the only reason to adopt one is to stop maintaining two.
#
# No frontmatter translation step exists, and none may be added: a skill is
# delivered byte-for-byte or not at all, because a file patched in transit is a
# second version of itself that no reader of the upstream copy can see. Locally
# authored dryvist skills carry the Hermes metadata contract. Imported skills
# retain their upstream contract and are checked separately for arrival.
#
# Their version sits under `metadata:`, not at the top level, and that is not a
# stylistic difference. claude-code-plugins validates every SKILL.md against the
# agentskills.io spec, whose top-level key set is closed — `version` and `author`
# are rejected there, and `metadata` is the sanctioned place for both. Since the
# marketplace holds the only authored copy, its spec wins, and
# checks/validate-skills.nix accepts a version at either depth. Do not "fix" the
# upstream file to match the older local convention; that reintroduces the fork
# this allowlist exists to end.
#
# ---------------------------------------------------------------------------
# Review record
#
# The two Dryvist marketplace entries below were reviewed for an unattended
# agent holding standing credentials.
# They are advisory: they describe how to choose and call a model the router
# already serves this agent, and grant no capability it does not already have.
# Specifically checked:
#
#   - Neither instructs the agent to acquire, read, or store a credential. Both
#     state the opposite — the agent never holds a provider key, and a router
#     failure is never answered by reaching for one.
#   - Spend is NOT bounded by the router — the proxy is storage-less and one
#     credential serves every caller, so there is nothing to meter per caller.
#     Both skills say so plainly and name the daily figure the agent must apply
#     itself, which is the only control that exists. This is the weakest point
#     of the pair and the reason the SOUL spend sentinel was inverted: an
#     unattended loop is exactly where self-enforcement fails silently. Revisit
#     it the moment router-side metering becomes real.
#   - Egress is constrained: free-tier endpoints log prompt content, so both
#     skills forbid sending secrets, infrastructure topology, or personal data
#     through them. That rule matters more unattended than interactively.
#   - Every delegated call is bounded by an explicit timeout, and no failure
#     path permits a silent fallback — which is what keeps an unattended run
#     from absorbing unbounded work without saying so.
#   - Neither embeds a model name, so neither can drift from the router's
#     served inventory the way the local copy deleted alongside this had.
#
# github-code-search was reviewed separately, and its risk shape is different
# from the delegation pair: it is the only shared skill that sends anything off
# the estate. Specifically checked:
#
#   - It is read-only and keyless. grep.app's MCP server is public and stateless
#     and exposes exactly one tool, `searchGitHub`; there is no account, no
#     token, and nothing for the agent to acquire or store. The skill grants no
#     capability beyond searching public source code — every result is already
#     world-readable on GitHub.
#   - It cannot write anywhere. Nothing in it creates an issue, a PR, a comment,
#     or a file; the output is search hits the agent reads.
#   - THE WEAK POINT, and the reason this entry exists as its own record: the
#     query string leaves the estate. grep.app receives it verbatim, and unlike
#     the workstation there is no human watching the query an unattended run
#     composes. The skill states the rule inline — never search for a hostname,
#     credential, internal path, or customer name — but that rule is enforced
#     only by the agent reading it, exactly like the spend figure above. It is
#     the same class of self-enforced control and fails the same way: silently.
#     Revisit if outbound egress ever gets a policy layer that could enforce it.
#   - A stated query rule is not the same as a redaction step, and none exists.
#     Nothing here scrubs a query before it is sent. Adding one would be the
#     real fix; it is not in this change, and that is a known gap, not an
#     oversight.
#   - It embeds no model name and reaches no router, so it cannot drift with the
#     served inventory.
#
# Browser Use was reviewed separately. It gives Hermes terminal-driven browser
# navigation using the existing loopback-only Chromium CDP endpoint; it does
# not grant a cloud Browser Use account or a new credential. Hermes already
# has terminal access, and the deployment verification proves only public
# documentation retrieval. Any authenticated browsing remains an explicit
# task-level decision under the existing Hermes credential policy.
# ---------------------------------------------------------------------------
[
  {
    input = "claude-code-plugins";
    skill = "ai-delegation/skills/delegate-to-router";
    target = "dryvist/delegate-to-router";
  }
  {
    input = "claude-code-plugins";
    skill = "ai-delegation/skills/openrouter-models";
    target = "dryvist/openrouter-models";
  }
  {
    # Literal code search over public GitHub, so the agent can find how a
    # problem was already solved before proposing custom code. Namespaced under
    # dryvist/ because it is authored in the marketplace alongside the pair
    # above, not vendored from a third party.
    input = "claude-code-plugins";
    skill = "github-workflows/skills/github-code-search";
    target = "dryvist/github-code-search";
  }
  {
    # Browser Use's official CLI skill. It has no Hermes-specific frontmatter,
    # so it intentionally lives outside dryvist/ and is copied verbatim.
    input = "browser-use";
    skill = "skills/browser-use";
    target = "browser-use";
  }
]
