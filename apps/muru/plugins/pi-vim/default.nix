# pi-vim — Vim keybindings extension for pi.
#
# No patching needed since 0.15.0: pi-vim detects the bun-compiled pi
# (process.versions.bun) and drives wl-copy/xclip/xsel directly instead of
# spawning a JS clipboard helper.
#
# Returns the entry point to pass to pi's -e flag.
{ callPackage, ... }:

"${callPackage ../../../../packages/pi-vim/package.nix { }}/index.ts"
