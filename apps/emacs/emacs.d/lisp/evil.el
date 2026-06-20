;;; evil.el --- Evil mode, leader key, and escape-quits-everything  -*- lexical-binding: t; -*-

(require 'evil)
(evil-mode 1)
(evil-set-undo-system 'undo-redo)

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
