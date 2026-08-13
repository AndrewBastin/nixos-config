# pi-ollama-cloud — Ollama Cloud provider extension for pi.
#
# Unlike pi-vim this needs no patching: it only uses bare imports of the packages
# pi itself bundles (@earendil-works/*, typebox), which pi's extension loader
# resolves from inside its own binary. Verified by loading it with `pi -e` — the
# ollama-cloud models show up in `--list-models`.
#
# Loaded as a directory, not a file, so pi reads the `pi.extensions` manifest in
# package.json rather than us hardcoding an entrypoint that upstream may move.
# Returns the directory path to pass to pi's -e flag.
#
# `lib`, `runCommand` and `pi` are accepted (and unused) so the auto-discovery in
# apps/muru/default.nix can pass the same arg set to every plugin.
{ lib, runCommand, callPackage, pi }:

callPackage ../../../../packages/pi-ollama-cloud/package.nix {}
