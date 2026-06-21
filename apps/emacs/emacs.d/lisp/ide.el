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

;; --- LSP via the built-in eglot -------------------------------------------
;; eglot already knows rust-analyzer, typescript-language-server and nixd; we
;; just auto-start it for the languages we use.  `eglot-ensure' in a mode hook
;; connects the server when such a buffer opens.
(dolist (hook '(rust-ts-mode-hook
                typescript-ts-mode-hook
                tsx-ts-mode-hook
                js-ts-mode-hook
                nix-mode-hook))
  (add-hook hook #'eglot-ensure))

;; Don't let code-action availability clutter the echo area. eglot's default
;; (`eldoc-hint margin') appends a "code action available" hint to the eldoc
;; output shown in the minibuffer, mixing it in with the hover/type info we do
;; want. Drop `eldoc-hint' and keep only the quiet `margin' fringe indicator.
(with-eval-after-load 'eglot
  (setq eglot-code-action-indications '(margin)))

;; --- Tree-sitter major modes (grammars provided by the flake) -------------
;; Map file extensions to the tree-sitter modes for richer highlighting.
(dolist (entry '(("\\.rs\\'"   . rust-ts-mode)
                 ("\\.ts\\'"   . typescript-ts-mode)
                 ("\\.tsx\\'"  . tsx-ts-mode)
                 ("\\.js\\'"   . js-ts-mode)
                 ("\\.json\\'" . json-ts-mode)))
  (add-to-list 'auto-mode-alist entry))

;; --- Hover documentation in a popup ---------------------------------------
;; eglot feeds documentation through eldoc.  By default `eldoc-doc-buffer'
;; (bound to `K') shows it in a separate window; `eldoc-box' renders the same
;; content in a childframe popup at point instead (see the `K' binding in
;; keybindings.el).  `eldoc-box-help-at-point' is the on-demand command; we just
;; need the package loaded so it (and its faces) are available.
(require 'eldoc-box)

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
