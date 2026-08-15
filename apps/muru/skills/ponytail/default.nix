# ponytail's skills (ponytail, ponytail-audit, ponytail-debt, ponytail-gain,
# ponytail-help, ponytail-review). The package ships them under skills/, which
# holds <skill-name>/SKILL.md subdirectories.
#
# `lib` is accepted (and unused) so the auto-discovery in apps/muru/default.nix
# can pass the same arg set to every skill.
{ lib, callPackage }:

"${callPackage ../../../../packages/ponytail-plugin/package.nix {}}/skills"
