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

  # On macOS, pure-GTK Emacs has no native Cocoa window — use the Mac port
  # (native Cocoa Emacs.app with mac-specific niceties). On Linux, pgtk is the
  # right native Wayland/Hyprland build (no XWayland). Everything downstream keys
  # off this binding (emacs.pkgs.withPackages), so grammars carry over unchanged.
  emacs =
    if isDarwin
    then pkgs.emacs-macport
    else pkgs.emacs-pgtk;
  emacsPkgs = emacs.pkgs;

  # Same package set as the source emacs-explore dev shell. `which-key` is built
  # into Emacs 30, so it needs no package here.
  emacsWithPkgs = emacsPkgs.withPackages (epkgs:
    let
      # Ghostel terminal (core + native Zig module) and its evil integration,
      # both built from ONE pinned dakra/ghostel rev so they can never drift
      # apart (see packages/ghostel).  Defined in packages/ghostel per this
      # repo's source-built-package convention, and built against THIS Emacs's
      # scope and headers (`emacsPackages = epkgs`, `emacs`) so its magit/
      # transient/evil match the rest of the set instead of pulling a second,
      # stale copy.
      ghostel = pkgs.callPackage ../../packages/ghostel/package.nix {
        emacsPackages = epkgs;
        inherit emacs;
      };
    in [
    epkgs.melpaPackages.evil
    # evil-collection: consistent vim-style bindings across ~150 special-mode
    # buffers (magit, dired, help, eww, info, ibuffer, …). Initialized in
    # lisp/evil.el. Our hand-rolled neotree/eglot keys in keybindings.el load
    # last and still win on overlap.
    epkgs.melpaPackages.evil-collection
    # nvim plugin parity (apps/nvim.nix): nvim-surround -> evil-surround
    # (ys/cs/ds), mini.comment -> evil-commentary (gcc, gc{motion}).  Both are
    # enabled in lisp/evil.el.
    epkgs.melpaPackages.evil-surround
    epkgs.melpaPackages.evil-commentary
    # More vim built-ins evil lacks: C-a/C-x number increment/decrement, the
    # matchit % (if/end, do/end, tag pairs), and the [3/14] search count
    # (evil-anzu bridges evil-search to anzu's mode-line display).  All three
    # are enabled in lisp/evil.el.
    epkgs.melpaPackages.evil-numbers
    epkgs.melpaPackages.evil-matchit
    epkgs.melpaPackages.evil-anzu
    epkgs.melpaPackages.kanagawa-themes
    epkgs.melpaPackages.nix-mode

    # QML has no built-in Emacs major mode (unlike the tree-sitter languages
    # below); this provides `qml-mode', which eglot attaches `qmlls' to.
    epkgs.melpaPackages.qml-mode

    # Ghostel terminal (core + native module) and its evil integration, both from
    # packages/ghostel — a single pinned rev (see the `ghostel' binding above),
    # replacing the old `epkgs.ghostel' + `melpaStablePackages.evil-ghostel' pair
    # that drifted across channels.
    ghostel
    ghostel.evil-ghostel

    # Completion / fuzzy-finding stack.
    epkgs.melpaPackages.vertico
    epkgs.melpaPackages.orderless
    epkgs.melpaPackages.marginalia
    epkgs.melpaPackages.consult
    epkgs.melpaPackages.consult-eglot

    # embark: act on the current minibuffer candidate (or thing at point) via a
    # type-aware keymap of actions, and — the reason it's here — `embark-export'
    # a whole completion session into a real buffer.  That's nvim's quickfix
    # workflow: consult-ripgrep -> grep-mode, consult-line -> occur-mode, both
    # of which implement `next-error' (see the ]q/[q keys in keybindings.el).
    # Configured in lisp/embark.el.
    epkgs.melpaPackages.embark
    # embark-consult supplies those exporters.  WITHOUT it, exporting a
    # consult-ripgrep session yields a generic collect buffer instead of a
    # grep-mode one — i.e. no quickfix list.  It also registers the default
    # actions for consult's own candidate categories (consult-grep,
    # consult-location), which lisp/embark.el's split commands delegate to.
    epkgs.melpaPackages.embark-consult
    # wgrep makes an exported grep-mode buffer editable (C-c C-p), so a
    # find-and-replace across every matched file is one buffer edit — vim's
    # `:cdo s/…/…/'.  embark-consult calls `wgrep-setup' on export by itself, so
    # no elisp config is needed; merely being on the load path is enough.
    # Emacs 31 makes this redundant via the built-in `grep-edit-mode'; drop it
    # when the emacs-pgtk pin moves to 31 (currently 30.2).
    epkgs.melpaPackages.wgrep

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
    # with-editor: the magit editor package.  Its `with-editor-mode' manages
    # the emacsclient ($EDITOR) buffers ghostel spawns for jj/git commit
    # messages — C-c C-c / :wq finish, C-c C-k / :q cancel.  Pulled in
    # transitively by magit anyway; listed explicitly because lisp/ghostel.el
    # requires it directly.
    epkgs.melpaPackages.with-editor
    # diff-hl: gitsigns equivalent — added/changed/deleted markers in the
    # fringe of every version-controlled buffer.  Enabled in lisp/ui.el.
    epkgs.melpaPackages.diff-hl
    epkgs.melpaPackages.neotree
    # vdiff: side-by-side diff engine used by lisp/diffview.el (our
    # diffview.nvim-style git UI) for the two-column file diff.
    epkgs.melpaPackages.vdiff

    # Syntax highlighting for jj's `*.jjdescription' commit-message files, which
    # the emacsclient-as-$EDITOR flow (see lisp/ghostel.el) opens. Autoloads an
    # `auto-mode-alist' entry, so it just works once on the load path.
    epkgs.melpaPackages.jjdescription

    # vc-jj: a Jujutsu backend for Emacs' built-in VC.  Registering it (see
    # lisp/vc.el) puts `JJ' ahead of `Git' in `vc-handled-backends', so in a
    # colocated jj repo `vc-mode' reports the jj change-id instead of git's
    # detached-HEAD hash — which is what the modeline's VC segment renders.
    # Also gives vc-diff / vc-log / vc-annotate on jj repos for free.
    epkgs.elpaPackages.vc-jj

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
    # LSP servers mirroring apps/nvim.nix. Bundled (like the three above) so the
    # editor works out of the box; a project's direnv flake can still shadow any
    # of these since the dev shell's PATH takes precedence over this suffix.
    pkgs.gopls
    pkgs.elixir-ls
    pkgs.pyright
    pkgs.bash-language-server
    pkgs.vscode-langservers-extracted          # vscode-json-language-server
    pkgs.dockerfile-language-server             # docker-langserver
    pkgs.docker-compose-language-service        # docker-compose-langserver
    pkgs.qt6.qtdeclarative                       # qmlls

    # Jujutsu tooling and support.
    # Required espectially in macOS to have access to Jujutsu
    pkgs.jjui
    pkgs.jujutsu
    pkgs.git # Needed for jjui and such to do git operations
  ];
  # `emacsWithPkgs` for its own `emacsclient`: ghostel sets $EDITOR to a bare
  # `emacsclient --socket-name=…' (lisp/ghostel.el section 5/6), and jjui is run
  # via `ghostel-exec' — a bare PTY program with NO shell, so nix-darwin's
  # shell-startup PATH repair never fires and jjui inherits Emacs's own exec-path.
  # Without this, `SPC G G' → jjui → describe can't resolve `emacsclient' on
  # macOS and the edit-in-Emacs handoff silently dies. Same build as the running
  # server, so the client/server protocol always matches.
  pathSuffix = lib.makeBinPath (runtimeTools ++ [ emacsWithPkgs ]);
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
