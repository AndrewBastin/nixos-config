#!/usr/bin/env bash
# `just bump' hook for the ghostel package.
#
# A plain `nix-update' would bump `src' (version + rev + hash) but leave the
# vendored Zig deps hash stale, so the next build would fail on a hash mismatch.
# `--custom-dep zigDeps' tells nix-update to also refresh that fixed-output
# derivation's hash, so `src' and the Zig deps move together.  (zigDeps is a flat
# passthru alias for the module's deps FOD — nix-update's --custom-dep resolves a
# single `pkg.<name>.outputHash', so a dotted `module.deps' would not work.)
#
# evil-ghostel needs no separate update: it is built from the SAME `src', so this
# one bump carries it along too.
#
# No `--version=branch' here on purpose: we follow the latest release TAG.
set -euo pipefail

nix-update --flake ghostel --custom-dep zigDeps "$@"
