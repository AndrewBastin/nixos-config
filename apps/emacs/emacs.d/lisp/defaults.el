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

;;; defaults.el ends here
