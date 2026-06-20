;;; ide.el --- LSP (eglot), tree-sitter major modes, mode switching  -*- lexical-binding: t; -*-

;; IDE setup mirroring my Neovim config (~/nixos-config/apps/nvim.nix).
;; Leader = SPC.  Packages + LSP servers come from the flake's dev shell.

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

;; --- Tree-sitter major modes (grammars provided by the flake) -------------
;; Map file extensions to the tree-sitter modes for richer highlighting.
(dolist (entry '(("\\.rs\\'"   . rust-ts-mode)
                 ("\\.ts\\'"   . typescript-ts-mode)
                 ("\\.tsx\\'"  . tsx-ts-mode)
                 ("\\.js\\'"   . js-ts-mode)
                 ("\\.json\\'" . json-ts-mode)))
  (add-to-list 'auto-mode-alist entry))

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
