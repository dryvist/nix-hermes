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
# No frontmatter translation step exists because none is needed: both entries
# below already carry the name/description/version that checks/validate-skills
# requires, plus a metadata.hermes block. A future entry lacking those must
# gain them upstream rather than being patched in transit.
#
# ---------------------------------------------------------------------------
# Review record
#
# Both entries reviewed for an unattended agent holding standing credentials.
# They are advisory: they describe how to choose and call a model the router
# already serves this agent, and grant no capability it does not already have.
# Specifically checked:
#
#   - Neither instructs the agent to acquire, read, or store a credential. Both
#     state the opposite — the agent never holds a provider key, and a router
#     failure is never answered by reaching for one.
#   - Spend is bounded by the router against this agent's own key, not by prose
#     and not by self-tracking that an unattended loop could quietly drift on.
#     A budget rejection is documented as a correct answer, not an obstacle.
#   - Egress is constrained: free-tier endpoints log prompt content, so both
#     skills forbid sending secrets, infrastructure topology, or personal data
#     through them. That rule matters more unattended than interactively.
#   - Every delegated call is bounded by an explicit timeout, and no failure
#     path permits a silent fallback — which is what keeps an unattended run
#     from absorbing unbounded work without saying so.
#   - Neither embeds a model name, so neither can drift from the router's
#     served inventory the way the local copy deleted alongside this had.
# ---------------------------------------------------------------------------
[
  {
    input = "ai-assistant-instructions";
    skill = "agentsmd/skills/delegate-to-router";
    target = "dryvist/delegate-to-router";
  }
  {
    input = "ai-assistant-instructions";
    skill = "agentsmd/skills/openrouter-models";
    target = "dryvist/openrouter-models";
  }
]
