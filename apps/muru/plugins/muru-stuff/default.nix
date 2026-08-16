# muru-stuff — custom extensions for muru, vendored into the flake.
#
# Unlike the packages in packages/ (which fetch from upstream and are tracked by
# `just bump`), this plugin is vendored: the extension source lives in this
# folder, copied from upstream mitsuhiko/agent-stuff (see the header of
# unified-edit.ts for the pinned commit and license). There is no upstream
# package to bump — updating means re-copying the file and ratifying the new
# commit in its header.
#
# Loaded as a directory, not a file, so pi reads the `pi.extensions` manifest
# in package.json rather than us hardcoding an entrypoint that may move. Returns
# the directory path to pass to pi's -e flag.
#
# `callPackage` and `pi` are accepted (and unused) so the auto-discovery in
# apps/muru/default.nix can pass the same arg set to every plugin.
{ lib, runCommand, callPackage, pi }:

runCommand "muru-stuff" {} ''
  cp -r ${./.} $out
''
