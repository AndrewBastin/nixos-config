# vc-jj, built from codeberg main because GNU ELPA is stuck at 0.5.
#
# Why this exists: MELPA's rolling diff-hl (>= 20260811) calls
# `vc-jj--process-lines' with a leading nil FILE-OR-LIST argument (see
# diff-hl's `diff-hl-resolved-revision', commit c9a5aec), which requires the
# `(file-or-list &rest args)' signature that only exists on codeberg main
# (vc-jj PR #158, merged 2026-03-01).  GNU ELPA still ships 0.5 with the old
# `(&rest args)' signature, so the nil lands in `call-process''s ARGS and every
# diff-hl diff against a jj repo dies with `(wrong-type-argument stringp nil)'
# — e.g. the "Error running timer 'diff-hl--update-buffer'" after a revert.
#
# Bumping: `just bump' runs `nix-update --version=branch' (the `version=branch'
# marker below), following codeberg master.  That is the right thing to track:
# master is what diff-hl's call convention targets, so following it keeps the
# two packages in agreement as long as diff-hl doesn't change the call again.
{
  lib,
  fetchFromGitea,
  emacsPackages,
  nix-update-script,
}:

let
  inherit (emacsPackages) melpaBuild;

  pname = "vc-jj";
  # Main is ahead of the v0.5 tag; commit date of the pinned rev below.
  version = "0.5-unstable-2026-07-27";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "emacs-jj-vc";
    repo = "vc-jj.el";
    rev = "17310449644cc527dfa6b8ca5320de4c33d1c7f3";
    hash = "sha256-koM7qbJbeAIf+0W0O4NR8ri31tft5MfdTTGM6M848d4=";
  };
in
melpaBuild {
  inherit pname version src;

  # Just the one .el; vc-jj-tests.el (same dir) stays out of the store path.
  files = ''("vc-jj.el")'';

  # Same single dependency nixpkgs' ELPA 0.5 derivation propagates (project.el
  # is built into Emacs 28+, so the header's `project' requirement needs no
  # package).
  packageRequires = [
    emacsPackages.compat
  ];

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = {
    homepage = "https://codeberg.org/emacs-jj-vc/vc-jj.el";
    description = "VC backend for the Jujutsu version control system";
    license = lib.licenses.gpl3Plus;
  };
}
