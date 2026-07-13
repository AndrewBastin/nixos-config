# Majutsu: a Magit-style Emacs porcelain for the Jujutsu (jj) VCS.
#
# Not on MELPA/ELPA, so it is built from source, pinned to a commit.
#
# This takes the whole `emacsPackages' set (rather than the usual per-dep args)
# on purpose: the flake auto-imports every packages/*/package.nix with the
# top-level `pkgs.callPackage' (see flake.nix), where `trivialBuild'/`magit'/…
# do NOT exist — but `pkgs.emacsPackages' does, so this stays auto-importable.
# apps/emacs then calls this with `emacsPackages = <its own overlaid+overridden
# emacs scope>' so Majutsu's magit/transient/… are the SAME instances as the
# rest of that Emacs's package set (no duplicate magit).
#
# Requires jj >= 0.40 at runtime; the system ships 0.43 (see modules/dev-essentials).
{
  lib,
  emacsPackages,
  fetchFromGitHub,
}:

emacsPackages.trivialBuild {
  pname = "majutsu";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "0WD0";
    repo = "majutsu";
    rev = "fd31b8c87bd53f5404b82386a0b1d7076bde83dc";
    hash = "sha256-KKZQcILlUiPasIAYPpzkeWmFlDE5jPksCDMEBi4T/F0=";
  };

  # Hard deps from majutsu.el's Package-Requires (compat/transient/magit/consult/
  # plz) plus with-editor (magit's editor integration).  On the byte-compile path
  # here and propagated at runtime.
  packageRequires = with emacsPackages; [
    magit
    transient
    compat
    consult
    plz
    with-editor
  ];

  meta = {
    description = "Magit-style Emacs porcelain for the Jujutsu (jj) VCS";
    homepage = "https://github.com/0WD0/majutsu";
    license = lib.licenses.gpl3Plus;
  };
}
