;;; vc-watch.el --- Refresh the modeline VC segment on VCS state changes  -*- lexical-binding: t; -*-

;; The modeline's VC segment (`my/ml-vc-branch') falls back to the ACTIVE DIR's
;; branch/change-id (`my/ml--active-vc' in modeline.el) when no file is open.
;; That ref must stay fresh when the VCS state changes by ANY actor — an
;; interactive `cd', a background job, a Claude Code agent running `jj'/`git' —
;; not just an interactive command.  Emacs' VC is pull-based, so we LISTEN with
;; `file-notify' (inotify) on the active dir's VCS metadata:
;;   jj  -> <root>/.jj/repo/op_heads/heads/  (rotates on every jj operation)
;;   git -> <root>/.git/                     (HEAD rewritten on checkout)
;; and refresh (invalidate the memo + `force-mode-line-update') on change.
;;
;; One watch at a time (the active dir is global).  `my/vc-watch-repoint' is
;; advised :after onto `my/neotree-follow' — the single seam all three active-dir
;; changes (terminal focus, cd/OSC7, pin/unpin) already funnel through — so the
;; watch re-points whenever the active dir may have changed.  Events are debounced
;; and we repaint only when the ref actually changed.
(require 'filenotify)
(require 'vc-git)                        ; `vc-git-root'

(declare-function my/active-dir "ghostel" ())
(declare-function my/ml--active-vc "modeline" ())
(declare-function my/ml--active-vc-invalidate "modeline" ())
(declare-function vc-jj-root "vc-jj" (file))
(defvar my/ml--active-vc-cache)          ; defined in modeline.el

(defvar my/vc-watch--descriptor nil "Current `file-notify' watch descriptor, or nil.")
(defvar my/vc-watch--watched-dir nil "Metadata dir currently watched, or nil.")
(defvar my/vc-watch--timer nil "Pending debounce timer, or nil.")

(defun my/vc-watch--target-dir (root backend)
  "Metadata directory under ROOT to watch for BACKEND state changes, or nil."
  (pcase backend
    ('JJ  (expand-file-name ".jj/repo/op_heads/heads/" root))
    ('Git (expand-file-name ".git/" root))))

(defun my/vc-watch--refresh ()
  "Recompute the active-dir ref; repaint all mode lines only if it changed."
  (setq my/vc-watch--timer nil)
  (let ((old (and (fboundp 'my/active-dir) (boundp 'my/ml--active-vc-cache)
                  (cdr (assoc (my/active-dir) my/ml--active-vc-cache)))))
    (my/ml--active-vc-invalidate)
    (unless (equal old (my/ml--active-vc))
      (force-mode-line-update t))))

(defun my/vc-watch--on-change (_event)
  "Debounced `file-notify' callback: (re)schedule a refresh ~0.3s out."
  (when (timerp my/vc-watch--timer) (cancel-timer my/vc-watch--timer))
  (setq my/vc-watch--timer (run-with-timer 0.3 nil #'my/vc-watch--refresh)))

(defun my/vc-watch-repoint (&rest _)
  "Point the `file-notify' watch at the active dir's VCS metadata.
No-op when the target is unchanged, so it is cheap to call from the active-dir
seams.  Tears down the old watch, invalidates the ref memo, and repaints."
  (let* ((dir     (and (fboundp 'my/active-dir) (my/active-dir)))
         (backend (and dir (vc-responsible-backend dir t)))
         (root    (and backend (ignore-errors
                                 (pcase backend
                                   ('JJ  (vc-jj-root dir))
                                   ('Git (vc-git-root dir))))))
         (target  (and root (my/vc-watch--target-dir root backend))))
    (unless (equal target my/vc-watch--watched-dir)
      (when my/vc-watch--descriptor
        (ignore-errors (file-notify-rm-watch my/vc-watch--descriptor)))
      (when (timerp my/vc-watch--timer)
        (cancel-timer my/vc-watch--timer)
        (setq my/vc-watch--timer nil))
      (setq my/vc-watch--descriptor nil
            my/vc-watch--watched-dir target)
      (when (fboundp 'my/ml--active-vc-invalidate) (my/ml--active-vc-invalidate))
      ;; NOTE: git worktrees/submodules use a `.git' FILE, not a directory, so
      ;; `file-directory-p' is nil below and no live watch gets established for
      ;; that repo — the ref still refreshes on active-dir change, just not on
      ;; external commits made to it while it's the active dir.
      (when (and target (file-directory-p target))
        (setq my/vc-watch--descriptor
              (ignore-errors
                (file-notify-add-watch target '(change) #'my/vc-watch--on-change))))
      (force-mode-line-update t))))

(defun my/vc-watch-teardown ()
  "Remove the watch and cancel any pending timer (on `kill-emacs-hook')."
  (when my/vc-watch--descriptor
    (ignore-errors (file-notify-rm-watch my/vc-watch--descriptor)))
  (when (timerp my/vc-watch--timer) (cancel-timer my/vc-watch--timer))
  (setq my/vc-watch--descriptor nil
        my/vc-watch--watched-dir nil
        my/vc-watch--timer nil))

;; All three active-dir seams (terminal focus, cd/OSC7, pin/unpin) funnel through
;; `my/neotree-follow'; advise it :after to re-point the watch on any active-dir
;; change.  `my/vc-watch-repoint' is a no-op when the target is unchanged.
(advice-add 'my/neotree-follow :after #'my/vc-watch-repoint)
(add-hook 'kill-emacs-hook #'my/vc-watch-teardown)
(my/vc-watch-repoint)                    ; establish the initial watch at startup

;;; vc-watch.el ends here
