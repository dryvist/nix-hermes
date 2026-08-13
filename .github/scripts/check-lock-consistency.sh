#!/usr/bin/env bash
# Assert flake.lock matches the inputs named in flake.nix.
#
# `nix flake check` does NOT assert this. Given a stale lock it silently
# rewrites the file in the working tree and exits 0 — so CI goes green, the
# rewrite is discarded with the runner, and the merge lands a flake.nix naming
# one revision beside a lock naming another. Verified by committing a revision
# bump without a lock update: nix flake check passed and left flake.lock dirty.
#
# --no-update-lock-file turns exactly that case into an error, which is the
# whole point of this script.
set -o errexit
set -o nounset
set -o pipefail

if nix flake metadata --no-update-lock-file >/dev/null; then
  echo "flake.lock is consistent with flake.nix"
  exit 0
fi

echo "::error::flake.lock is stale for the inputs named in flake.nix." >&2
echo "Run 'nix flake lock' and commit the result." >&2
exit 1
