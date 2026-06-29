;;; ide.el --- LSP (eglot), tree-sitter major modes, mode switching  -*- lexical-binding: t; -*-

;; IDE setup mirroring my Neovim config (~/nixos-config/apps/nvim.nix).
;; Leader = SPC.  Packages + LSP servers come from the flake's dev shell.

;; --- Per-project environment via direnv -----------------------------------
;; `envrc-global-mode' applies each project's direnv environment buffer-locally,
;; so the subprocesses eglot spawns (rust-analyzer, etc.) inherit the project's
;; flake dev shell: cargo, rustc and the toolchain sysroot.  Enable it before
;; eglot attaches.  `eglot-ensure' defers its connection to `post-command-hook',
;; by which point envrc has already applied the buffer's env.  Each project
;; needs an `.envrc' (`use flake') that has been `direnv allow'-ed once.
(require 'envrc)
(envrc-global-mode 1)

;; By default envrc announces a load by dumping every environment variable it
;; touched ("+PATH ~PATH +CARGO_HOME ..."), a wall of text in the echo area.
;; `envrc--show-summary' is only called on a genuine direnv export (cached
;; re-applies stay silent), so override it to keep that timing but just print a
;; short confirmation instead.
(with-eval-after-load 'envrc
  (advice-add 'envrc--show-summary :override
              (lambda (_result directory)
                (message "direnv: loaded (%s)"
                         (abbreviate-file-name (directory-file-name directory))))))

;; --- LSP via the built-in eglot -------------------------------------------
;; eglot already knows most of these servers (rust-analyzer,
;; typescript-language-server, nixd, gopls, pyright, bash-language-server,
;; docker-langserver, vscode-json-language-server); the rest get custom
;; `eglot-server-programs' entries below.  `eglot-ensure' in a mode hook
;; connects the server when such a buffer opens.  This list mirrors the LSP
;; servers wired up in my Neovim config (~/nixos-config/apps/nvim.nix).
(dolist (hook '(rust-ts-mode-hook
                typescript-ts-mode-hook
                tsx-ts-mode-hook
                js-ts-mode-hook
                nix-mode-hook
                go-ts-mode-hook
                elixir-ts-mode-hook
                heex-ts-mode-hook
                json-ts-mode-hook
                python-ts-mode-hook
                bash-ts-mode-hook
                dockerfile-ts-mode-hook
                docker-compose-ts-mode-hook
                qml-mode-hook))
  (add-hook hook #'eglot-ensure))

;; Don't let code-action availability clutter the echo area. eglot's default
;; (`eldoc-hint margin') appends a "code action available" hint to the eldoc
;; output shown in the minibuffer, mixing it in with the hover/type info we do
;; want. Drop `eldoc-hint' and keep only the quiet `margin' fringe indicator.
(with-eval-after-load 'eglot
  (setq eglot-code-action-indications '(margin))

  ;; Servers eglot doesn't know how to launch out of the box, or that nixpkgs
  ;; ships under a different binary name than eglot's default expects.  Each is
  ;; prepended, so it wins over any built-in entry for the same mode.
  ;;
  ;; - elixir-ls: eglot's default hunts for `language_server.sh'/`start_lexical.sh',
  ;;   but nixpkgs wraps ElixirLS as a single `elixir-ls' binary (handles .heex too).
  ;; - docker-compose-langserver: no built-in entry; `--stdio' like the Neovim setup.
  ;; - qmlls: no built-in entry and no QML mode in Emacs (we add `qml-mode' as a pkg).
  (dolist (entry '(((elixir-ts-mode heex-ts-mode) "elixir-ls")
                   (docker-compose-ts-mode "docker-compose-langserver" "--stdio")
                   (qml-mode "qmlls")))
    (add-to-list 'eglot-server-programs entry)))

;; --- LSP project root: detect the language project, not the working dir ----
;; eglot resolves its server root through `project-current' (hence
;; `project-find-functions'), binding `eglot-lsp-context' to t while it does.
;; Our pinned/terminal working-dir backend (`my/active-project', ghostel.el)
;; bows out in that context, so here we add language-project detection à la
;; nvim's lspconfig `root_pattern': walk up from the file to the nearest
;; directory holding a build/root marker (e.g. Cargo.toml for rust-analyzer).
;; This roots rust-analyzer at a nested crate like modules/.../hyprland-info,
;; independent of where neotree / SPC f are pointed.  No marker ⇒ nil, so eglot
;; falls through to `project-try-vc' (the VC root, e.g. for nixd at the flake).
(defvar my/project-root-markers
  '("Cargo.toml" "rust-project.json" "go.mod" "package.json" "tsconfig.json"
    "pyproject.toml" "setup.py" "setup.cfg" "mix.exs")
  "Files whose presence marks a language project root, like nvim's `root_pattern'.")

(defun my/eglot-project (dir)
  "A `project-find-functions' entry: nearest ancestor of DIR holding a root marker.
Active only under `eglot-lsp-context' (i.e. when eglot asks), so navigation
commands keep following the pinned/terminal working dir."
  (when (bound-and-true-p eglot-lsp-context)
    (when-let* ((root (locate-dominating-file
                       dir
                       (lambda (d)
                         (seq-some (lambda (m) (file-exists-p (expand-file-name m d)))
                                   my/project-root-markers)))))
      (cons 'transient (expand-file-name root)))))

(with-eval-after-load 'project
  (add-to-list 'project-find-functions #'my/eglot-project))

;; Docker Compose files are YAML, so derive a mode from `yaml-ts-mode' for
;; highlighting; the distinct mode is what lets eglot attach the compose
;; language server (above) instead of a generic YAML server.
(define-derived-mode docker-compose-ts-mode yaml-ts-mode "Compose"
  "Major mode for Docker Compose files: YAML tree-sitter + compose LSP.")

;; --- Tree-sitter major modes (grammars provided by the flake) -------------
;; Map file extensions to the tree-sitter modes for richer highlighting.
;; These modes are autoloaded, but some (e.g. `elixir-ts-mode') only register
;; their own `auto-mode-alist' entries when the package loads, which nothing
;; here triggers -- so without an explicit mapping such files open in
;; Fundamental mode. Map them ourselves to be sure.
(dolist (entry '(("\\.rs\\'"      . rust-ts-mode)
                 ("\\.ts\\'"      . typescript-ts-mode)
                 ("\\.tsx\\'"     . tsx-ts-mode)
                 ("\\.js\\'"      . js-ts-mode)
                 ("\\.json\\'"    . json-ts-mode)
                 ("\\.exs?\\'"    . elixir-ts-mode)
                 ("mix\\.lock\\'" . elixir-ts-mode)
                 ("\\.heex\\'"    . heex-ts-mode)
                 ("\\.go\\'"      . go-ts-mode)
                 ("\\.py\\'"      . python-ts-mode)
                 ("\\.\\(sh\\|bash\\)\\'" . bash-ts-mode)
                 ("\\.qml\\'"     . qml-mode)
                 ;; Compose files first so they win over the generic Dockerfile/
                 ;; YAML matches below.
                 ("\\(?:^\\|/\\)\\(?:docker-\\)?compose\\(?:\\.[^/]*\\)?\\.ya?ml\\'"
                  . docker-compose-ts-mode)
                 ("\\(?:^\\|/\\)\\(?:Containerfile\\|Dockerfile\\)\\(?:\\.[^/]*\\)?\\'"
                  . dockerfile-ts-mode)
                 ("\\.dockerfile\\'" . dockerfile-ts-mode)))
  (add-to-list 'auto-mode-alist entry))

;; --- Hover documentation in a popup ---------------------------------------
;; eglot feeds documentation through eldoc.  By default `eldoc-doc-buffer'
;; (bound to `K') shows it in a separate window; `eldoc-box' renders the same
;; content in a childframe popup at point instead (see the `K' binding in
;; keybindings.el).  `eldoc-box-help-at-point' is the on-demand command; we just
;; need the package loaded so it (and its faces) are available.
(require 'eldoc-box)

;; `K' toggles the hover-doc popup: show it, or dismiss it if it's already up.
;; eldoc-box's own behaviour is that a second `K' (`eldoc-box-help-at-point')
;; *focuses* the childframe instead of closing it — and `q' to quit there is
;; bound via `local-set-key', which evil's normal-state `q' (`evil-record-macro')
;; shadows.  Toggling sidesteps that entirely: pressing `K' again just closes it.
(defun my/eldoc-doc-toggle ()
  "Show the eldoc-box hover-doc popup, or close it if it is already visible."
  (interactive)
  (if (and (fboundp 'eldoc-box--frame-visible-p) (eldoc-box--frame-visible-p))
      (eldoc-box-quit-frame)
    (eldoc-box-help-at-point)))

;; `SPC k' opens the SAME documentation in a real split below and focuses it, for
;; reading/scrolling long docs — the transient `K' childframe can't be scrolled
;; comfortably (focusing it lands you in a buffer where evil's `q' fights us).
;; The `*eldoc*' buffer is `special-mode', which evil would put in normal state
;; (so `q' = record-macro); we force MOTION state instead, matching help-mode —
;; vim motions scroll, and `q' falls through to `quit-window' to close the split.
(defun my/eldoc-doc-split ()
  "Open the symbol-at-point ElDoc documentation in a split below and focus it.
Read with vim motions; `q' closes the split.  `K' shows the quick popup."
  (interactive)
  (unless (buffer-live-p eldoc--doc-buffer)
    (eldoc))                              ; force a lookup if nothing is cached yet
  (unless (buffer-live-p eldoc--doc-buffer)
    (user-error "No ElDoc documentation at point yet — try again in a moment"))
  ;; eldoc names the buffer with a leading space (hidden) until shown
  ;; interactively; strip it so the split reads cleanly.
  (with-current-buffer eldoc--doc-buffer
    (when (string-prefix-p " " (buffer-name))
      (rename-buffer (string-trim-left (buffer-name)) t)))
  (let ((win (display-buffer
              eldoc--doc-buffer
              '((display-buffer-reuse-window display-buffer-below-selected)
                (window-height . 0.4)))))
    (when (window-live-p win)
      (select-window win)
      (when (fboundp 'evil-motion-state) (evil-motion-state)))))

;; Helper for vim's `<leader>cf' (change filetype = switch major mode).
(defun my/change-major-mode ()
  "Prompt for a major mode and switch the current buffer to it."
  (interactive)
  (funcall (intern (completing-read
                    "Major mode: " obarray
                    (lambda (s) (and (commandp s)
                                     (string-suffix-p "-mode" (symbol-name s))))
                    t))))

;;; ide.el ends here
