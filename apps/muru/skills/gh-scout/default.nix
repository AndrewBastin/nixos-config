# gh-scout's skills (exploring-github). The package copies the repo's skills/
# directory into $out, so the store path itself holds <skill-name>/SKILL.md
# subdirectories (no /skills suffix needed, unlike ponytail).
#
# `lib` is accepted (and unused) so the auto-discovery in apps/muru/default.nix
# can pass the same arg set to every skill.
{ lib, callPackage }:

"${callPackage ../../../../packages/gh-scout-skills/package.nix {}}"
