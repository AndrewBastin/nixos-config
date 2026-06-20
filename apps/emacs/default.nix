# Self-contained, store-baked Emacs 
#
# Expects `pkgs` to ALREADY have the nix-community/emacs-overlay overlay applied
# (it provides emacs-pgtk's melpa/melpaStable package sets and treesit grammars),
# the same way apps/nvim.nix expects a nixvim-augmented input. See flake.nix and
# modules/dev-essentials/default.nix where this is imported.
{ pkgs, ... }:
let
  inherit (pkgs) lib;

  # nixpkgs' ghostel Elisp builds its native (Zig) module from source, which
  # fails on Darwin (DarwinSdkNotFound). This transform swaps in a prebuilt
  # module instead; see ./ghostel.nix. Applied over the whole Emacs package scope
  # so `evil-ghostel` (whose `ghostel` dep resolves to this package) gets it too.
  withPrebuiltGhostelModule = pkgs.callPackage ./ghostel.nix { };

  emacs = pkgs.emacs-pgtk;
  emacsPkgs = emacs.pkgs.overrideScope (final: prev: {
    ghostel = withPrebuiltGhostelModule prev.ghostel;
  });

  # Same package set as the source emacs-explore dev shell. `which-key` is built
  # into Emacs 30, so it needs no package here.
  emacsWithPkgs = emacsPkgs.withPackages (epkgs: [
    epkgs.melpaPackages.evil
    epkgs.melpaPackages.kanagawa-themes
    epkgs.melpaPackages.nix-mode

    # Ghostel terminal: Elisp + bundled prebuilt native module + evil integration.
    epkgs.ghostel
    epkgs.melpaStablePackages.evil-ghostel

    # Completion / fuzzy-finding stack.
    epkgs.melpaPackages.vertico
    epkgs.melpaPackages.orderless
    epkgs.melpaPackages.marginalia
    epkgs.melpaPackages.consult
    epkgs.melpaPackages.consult-eglot

    # In-buffer completion popup at point (corfu = vertico's sibling) plus
    # `cape' completion-at-point backends (dabbrev, file, …).
    epkgs.melpaPackages.corfu
    epkgs.melpaPackages.cape

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
        --suffix PATH : "${lib.makeBinPath runtimeTools}"
    done
  '';
}
