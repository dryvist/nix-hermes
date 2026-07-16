# Allowlist for sharing WORKSTATION skills (nix-ai / Claude plugin ecosystem)
# into the Hermes bundle. Deliberately EMPTY: Hermes runs unattended with
# standing credentials, so every shared skill needs a human safety review
# before it enters — a workstation skill's assumptions (interactive user,
# reversible actions, no autonomous cron context) do not transfer for free.
#
# Entry shape (when populated):
#   { input = "<flake input holding the skill>"; skill = "<path within it>"; }
#
# Populating this list also requires adding the source flake input and a copy
# + frontmatter-translation step in lib/bundle.nix (inject a
# metadata.hermes block); that machinery is intentionally not built ahead of
# the first reviewed entry.
[ ]
