# Self-contained, store-baked Emacs 
#
# Expects `pkgs` to ALREADY have the nix-community/emacs-overlay overlay applied
# (it provides emacs-pgtk's melpa/melpaStable package sets and treesit grammars),
# the same way apps/nvim.nix expects a nixvim-augmented input. See flake.nix and
# modules/dev-essentials/default.nix where this is imported.
{ pkgs, ... }:
let
  inherit (pkgs) lib;

  emacs = pkgs.emacs-pgtk;

  # Prebuilt native (Zig) module + matching stable Elisp, kept in lockstep.
  ghostel = pkgs.callPackage ./ghostel.nix { inherit emacs; };

  # Same package set as the source emacs-explore dev shell. `which-key` is built
  # into Emacs 30, so it needs no package here.
  emacsWithPkgs = emacs.pkgs.withPackages (epkgs: [
    epkgs.melpaPackages.evil
    epkgs.melpaPackages.kanagawa-themes
    epkgs.melpaPackages.nix-mode

    # Ghostel terminal: the native module's matching Elisp + evil integration.
    ghostel.elisp
    epkgs.melpaStablePackages.evil-ghostel

    # Completion / fuzzy-finding stack.
    epkgs.melpaPackages.vertico
    epkgs.melpaPackages.orderless
    epkgs.melpaPackages.marginalia
    epkgs.melpaPackages.consult
    epkgs.melpaPackages.consult-eglot

    epkgs.melpaPackages.magit
    epkgs.melpaPackages.neotree

    # Per-project environment via direnv. `envrc` applies each project's direnv
    # env buffer-locally so eglot's subprocesses (rust-analyzer, etc.) inherit
    # the project's flake dev shell; `inheritenv` keeps that env correct in
    # subprocesses spawned from temp buffers.
    epkgs.melpaPackages.envrc
    epkgs.melpaPackages.inheritenv

    epkgs.treesit-grammars.with-all-grammars
  ]);

  # Tools eglot launches and consult shells out to. Bundled so the editor is
  # self-contained (the source had these in the dev shell).
  runtimeTools = [
    pkgs.ripgrep
    pkgs.fd
    # `direnv` itself, so the store-baked Emacs can run it regardless of which
    # session launched it (e.g. the fern keybind, not a shell that already
    # loaded direnv). `envrc` shells out to this.
    pkgs.direnv
    pkgs.rust-analyzer
    pkgs.typescript-language-server
    pkgs.nixd
  ];
in
pkgs.symlinkJoin {
  name = "emacs-explore";
  paths = [ emacsWithPkgs ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    for bin in "$out/bin/emacs" "$out"/bin/emacs-*; do
      [ -e "$bin" ] || continue
      wrapProgram "$bin" \
        --add-flags "--init-directory ${./emacs.d}" \
        --suffix PATH : "${lib.makeBinPath runtimeTools}" \
        --set-default GHOSTEL_MODULE_PATH "${ghostel}/lib/ghostel"
    done
  '';
}
