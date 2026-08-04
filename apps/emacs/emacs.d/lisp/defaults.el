;;; defaults.el --- Workflow defaults: auto-revert, persistence, winner  -*- lexical-binding: t; -*-

;; Files change under Emacs constantly here: jj commands, Claude Code and
;; formatters all rewrite files while their buffers stay open.  Auto-revert
;; keeps buffers in sync with disk; buffers with unsaved edits are left alone.
(global-auto-revert-mode 1)

;; Persistent state across sessions.  early-init.el already points each mode's
;; save file at XDG_STATE_HOME — these enable the modes themselves.
(savehist-mode 1)     ; minibuffer histories — vertico sorts candidates by them
(setq recentf-max-saved-items 100)      ; the default (20) forgets too fast
(recentf-mode 1)      ; recent files — consult-buffer (SPC b b) lists them
(save-place-mode 1)   ; reopen a file at the position point was at

;; Undo for window layouts: `winner-undo' (C-c <left>) restores the previous
;; arrangement after an accidental close/maximize, C-c <right> redoes.
(winner-mode 1)

;; Indentation matches the nvim config (`opts' in apps/nvim.nix): spaces only
;; (expandtab), two columns wide (tabstop 2).  `evil-shift-width' — nvim's
;; shiftwidth, what `>>' moves by — is already 2 in evil.el, and evil rounds to
;; it (`evil-shift-round') by default, so `<<'/`>>' match shiftround too.
;; `tab-width' is also what smie falls back to, which covers nix-mode.
(setq-default indent-tabs-mode nil
              tab-width 2
              standard-indent 2)

;; Major modes that carry their own offset rather than reading `tab-width'.
;; Plain `setq' is enough despite these modes loading later: `defcustom' never
;; clobbers a value that is already set.  Modes left out (typescript/tsx, json,
;; yaml, dockerfile, elixir, heex, toml, c) already default to 2.
(setq css-indent-offset 2           ; css-ts-mode
      go-ts-mode-indent-offset 2    ; nvim expandtabs Go too, so no hard tabs
      js-indent-level 2             ; js-ts-mode, json-ts-mode, qml-mode
      python-indent-offset 2        ; only for files python can't guess from
      rust-ts-mode-indent-offset 2
      sh-basic-offset 2)            ; bash-ts-mode

;; `go-ts-mode' hard-codes `indent-tabs-mode' to t (gofmt's convention) and so
;; ignores the default above; nvim's expandtab has no such exception, so undo
;; it.  `makefile-mode' does the same thing but genuinely needs real tabs, so
;; it is deliberately left alone.
(add-hook 'go-ts-mode-hook (lambda () (setq indent-tabs-mode nil)))

;;; defaults.el ends here
