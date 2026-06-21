# Self-contained, store-baked Emacs 
#
# Expects `pkgs` to ALREADY have the nix-community/emacs-overlay overlay applied
# (it provides emacs-pgtk's melpa/melpaStable package sets and treesit grammars),
# the same way apps/nvim.nix expects a nixvim-augmented input. See flake.nix and
# modules/dev-essentials/default.nix where this is imported.
{ pkgs, ... }:
let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # nixpkgs' ghostel Elisp builds its native (Zig) module from source, which
  # fails on Darwin (DarwinSdkNotFound). This transform swaps in a prebuilt
  # module instead; see ./ghostel.nix. Applied over the whole Emacs package scope
  # so `evil-ghostel` (whose `ghostel` dep resolves to this package) gets it too.
  withPrebuiltGhostelModule = pkgs.callPackage ./ghostel.nix { };

  # On macOS, pure-GTK Emacs has no native Cocoa window — use the Mac port
  # (native Cocoa Emacs.app with mac-specific niceties). On Linux, pgtk is the
  # right native Wayland/Hyprland build (e.g. fern). Everything downstream keys
  # off this binding (emacs.pkgs.overrideScope / withPackages), so the ghostel
  # override and grammars carry over unchanged.
  emacs =
    if isDarwin
    then pkgs.emacs-macport
    else pkgs.emacs-pgtk;
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

    # Show eldoc (eglot hover) docs in a childframe popup at point instead of a
    # separate window. Same childframe style as corfu-popupinfo.
    epkgs.melpaPackages.eldoc-box

    # eglot renders LSP hover/signature docs (rust-analyzer etc. send Markdown)
    # via `gfm-view-mode', which lives in markdown-mode. Without it eglot falls
    # back to showing raw Markdown; with it the docs are fontified and code
    # blocks are highlighted natively.
    epkgs.melpaPackages.markdown-mode

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
  pathSuffix = lib.makeBinPath runtimeTools;
  initDir = ./emacs.d;
in
if isDarwin then
  # macOS: running the raw Emacs binary (what a wrapProgram bin/emacs does) never
  # registers as a foreground GUI app — no Dock icon, no keyboard focus, and
  # invisible to aerospace. A GUI app must be launched as its `.app` bundle via
  # `open` (Launch Services). So here we:
  #   1. copy Emacs.app (tiny — ~1.2M; lisp/eln live in the store, referenced via
  #      EMACSLOADPATH) and re-wrap its Mach-O launcher so --init-directory and
  #      the runtime-tools PATH are baked in (a bash launcher would itself break
  #      GUI launch, so this must stay a binary wrapper);
  #   2. ship `emacs-gui`, which `open`s that bundle — this is what the aerospace
  #      keybind runs;
  #   3. keep a normal terminal `emacs` (+ emacsclient et al.) for CLI use.
  pkgs.runCommand "emacs-explore" { nativeBuildInputs = [ pkgs.makeBinaryWrapper ]; } ''
    mkdir -p $out/bin $out/Applications

    # Symlink everything except bin/ and Applications/, which we customise.
    for entry in ${emacsWithPkgs}/*; do
      base=$(basename "$entry")
      case "$base" in
        bin|Applications) ;;
        *) ln -s "$entry" "$out/$base" ;;
      esac
    done

    # bin/: passthrough every tool, then override `emacs` with our flags/PATH and
    # add the GUI launcher. Only `emacs` gets --init-directory (not emacsclient).
    for bin in ${emacsWithPkgs}/bin/*; do
      ln -s "$bin" "$out/bin/$(basename "$bin")"
    done
    rm "$out/bin/emacs"
    makeWrapper "${emacsWithPkgs}/bin/emacs" "$out/bin/emacs" \
      --add-flags "--init-directory ${initDir}" \
      --suffix PATH : "${pathSuffix}"
    makeWrapper /usr/bin/open "$out/bin/emacs-gui" \
      --add-flags "-a $out/Applications/Emacs.app"

    # Applications/: real copy so we can re-wrap the bundle's Mach-O entry point.
    cp -R ${emacsWithPkgs}/Applications/Emacs.app "$out/Applications/"
    chmod -R u+w "$out/Applications/Emacs.app"
    wrapProgram "$out/Applications/Emacs.app/Contents/MacOS/Emacs" \
      --add-flags "--init-directory ${initDir}" \
      --suffix PATH : "${pathSuffix}"
  ''
else
  pkgs.symlinkJoin {
    name = "emacs-explore";
    paths = [ emacsWithPkgs ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for bin in "$out/bin/emacs" "$out"/bin/emacs-*; do
        [ -e "$bin" ] || continue
        wrapProgram "$bin" \
          --add-flags "--init-directory ${initDir}" \
          --suffix PATH : "${pathSuffix}"
      done
    '';
  }
