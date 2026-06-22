;;; evil.el --- Evil mode, leader key, and escape-quits-everything  -*- lexical-binding: t; -*-

;; evil-collection requires `evil-want-keybinding' to be nil BEFORE evil loads,
;; so evil skips its own `evil-keybindings' and lets evil-collection own the
;; per-mode bindings.  Otherwise `evil-collection-init' (below) warns about the
;; conflicting bindings evil already installed.
(setq evil-want-keybinding nil)

(require 'evil)
(evil-mode 1)
(evil-set-undo-system 'undo-redo)

;; --- evil-collection --------------------------------------------------------
;; Vim-style bindings for all the special-mode buffers evil leaves alone
;; (magit, dired, help, eww, info, ibuffer, xref, …).  This is what makes
;; link/button following work the obvious way: `go' in *Help*, RET in
;; info/eww/markdown, etc.
;;
;; Leave the minibuffer alone — vertico/consult and our custom escape-quits
;; behaviour own it — by keeping `evil-collection-setup-minibuffer' at its
;; default nil.  Init runs here (before keybindings.el), so the hand-rolled
;; neotree/eglot bindings there load last and win on any overlap.
(require 'evil-collection)
(evil-collection-init)

;; --- Leader key (SPC) -------------------------------------------------------
;; The leader is registered here; individual <leader>… bindings live in
;; keybindings.el (loaded later).
(evil-set-leader '(normal visual) (kbd "SPC"))

;; --- Escape quits everything ------------------------------------------------
;;; esc quits everything!
(defun minibuffer-keyboard-quit ()
  "Abort recursive edit.
In Delete Selection mode, if the mark is active, just deactivate it;
then it takes a second \\[keyboard-quit] to abort the minibuffer."
  (interactive)
  (if (and delete-selection-mode transient-mark-mode mark-active)
      (setq deactivate-mark  t)
    (when (get-buffer "*Completions*") (delete-windows-on "*Completions*"))
    (abort-recursive-edit)))

(define-key evil-normal-state-map [escape] 'keyboard-quit)
(define-key evil-visual-state-map [escape] 'keyboard-quit)
(define-key minibuffer-local-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-ns-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-completion-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-must-match-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-isearch-map [escape] 'minibuffer-keyboard-quit)

;;; evil.el ends here
