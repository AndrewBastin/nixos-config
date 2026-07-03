;;; diffview.el --- diffview.nvim-style side-by-side git UI  -*- lexical-binding: t; -*-

;; A self-contained, diffview.nvim-style git review UI.  `diffview-open'
;; pops a file panel (pinned in a left side-window) next to a vdiff
;; side-by-side of the selected file, covering staged/unstaged/untracked
;; changes.  magit is used purely as a git library (file lists + staging);
;; magit's own UI is never shown.  Exactly one session exists at a time, so
;; session state lives in the globals below.

(require 'magit)
(require 'seq)
;; Soft-require: the non-UI layers (model/panel/staging) must load and be
;; unit-testable even before vdiff is installed via Nix.  The diff pane
;; guards on `featurep' before calling into vdiff.
(require 'vdiff nil t)

(defgroup diffview nil
  "diffview.nvim-style git UI."
  :group 'tools)

;;;; Session state (global — one session at a time) -------------------

(defvar diffview--entries nil
  "Ordered list of entry plists for the active session.
Each entry is (:path PATH :status LETTER :section SYM), SYM one of
`unstaged', `staged', `untracked'.")

(defvar diffview--current-index 0
  "Index into `diffview--entries' of the currently-selected entry.")

(defvar diffview--saved-window-config nil
  "Window configuration to restore when the session closes.")

(defvar diffview--root nil
  "Absolute repo root for the active session.
All git commands and file reads anchor to this, so diffview works no
matter what `default-directory' the invoking buffer happens to have
\(e.g. a file opened in a subdirectory).")

;;;; Model ---------------------------------------------------------------

(defun diffview--section-rank (sym)
  "Sort rank for section SYM: unstaged<staged<untracked."
  (pcase sym ('unstaged 0) ('staged 1) ('untracked 2) (_ 3)))

(defun diffview--collect-entries ()
  "Return ordered entry plists for the session's repo.
Reuses magit's git plumbing (`magit-git-lines').  A path changed in
both index and worktree yields both a `staged' and an `unstaged'
entry.  Entries are ordered unstaged, then staged, then untracked."
  (let ((default-directory (or diffview--root default-directory))
        entries)
    (dolist (line (magit-git-lines "status" "--porcelain"))
      (when (>= (length line) 4)
        (let* ((x (aref line 0))
               (y (aref line 1))
               (raw (substring line 3))
               ;; Rename lines render as "old -> new"; keep the new path.
               (path (if (string-match " -> " raw)
                         (substring raw (match-end 0))
                       raw)))
          (if (and (eq x ??) (eq y ??))
              (push (list :path path :status "?" :section 'untracked) entries)
            (unless (memq x '(?\s ??))
              (push (list :path path :status (string x) :section 'staged) entries))
            (unless (memq y '(?\s ??))
              (push (list :path path :status (string y) :section 'unstaged) entries))))))
    (sort (nreverse entries)
          (lambda (a b)
            (< (diffview--section-rank (plist-get a :section))
               (diffview--section-rank (plist-get b :section)))))))

;;;; Panel ------------------------------------------------------------

(defface diffview-section-heading
  '((t :inherit magit-section-heading :weight bold))
  "Face for diffview panel section headings."
  :group 'diffview)

(defvar diffview-panel-mode-map (make-sparse-keymap)
  "Keymap for `diffview-panel-mode' (evil bindings added later).")

(define-derived-mode diffview-panel-mode special-mode "Diffview"
  "Major mode for the diffview file panel."
  (setq buffer-read-only t
        truncate-lines t))

(defconst diffview--sections
  '((unstaged  . "Unstaged changes")
    (staged    . "Staged changes")
    (untracked . "Untracked"))
  "Ordered (SYM . LABEL) alist for panel sections.")

(defface diffview-current-entry
  '((t :inherit hl-line :extend t :weight bold))
  "Line background/weight for the active entry (status colors show through)."
  :group 'diffview)

(defface diffview-current-marker
  '((t :inherit (font-lock-keyword-face) :weight bold))
  "Theme accent for the active entry's ▶ marker and filename.
Inherits `font-lock-keyword-face' so it picks up whatever accent the
active theme colors keywords with — no hardcoded color."
  :group 'diffview)

(defface diffview-status-added    '((t :inherit magit-diffstat-added))
  "Status letter for an added (A) entry." :group 'diffview)
(defface diffview-status-deleted  '((t :inherit magit-diffstat-removed))
  "Status letter for a deleted (D) entry." :group 'diffview)
(defface diffview-status-modified '((t :inherit warning))
  "Status letter for a modified (M) entry." :group 'diffview)
(defface diffview-status-untracked '((t :inherit font-lock-comment-face))
  "Status letter for an untracked (?) entry." :group 'diffview)

(defun diffview--status-face (letter)
  "Face for a one-char git status LETTER."
  (pcase letter
    ("A" 'diffview-status-added)
    ("D" 'diffview-status-deleted)
    ("?" 'diffview-status-untracked)
    (_   'diffview-status-modified)))

(defvar diffview--current-ovs nil
  "Overlays marking the current entry line in the panel.")

(defun diffview--update-current-highlight ()
  "Mark the currently-selected entry's line in the panel.
Draws a highlighted, bold line with a leading ▶ marker so the entry
being shown in the diff pane is obvious even when focus is elsewhere."
  (mapc #'delete-overlay diffview--current-ovs)
  (setq diffview--current-ovs nil)
  (let ((buf (get-buffer "*diffview*"))
        (entry (and diffview--entries
                    (nth diffview--current-index diffview--entries))))
    (when (and (buffer-live-p buf) entry)
      (with-current-buffer buf
        (save-excursion
          (goto-char (point-min))
          (let (found)
            (while (and (not found) (not (eobp)))
              (if (eq (get-text-property (point) 'diffview-entry) entry)
                  (setq found t)
                (forward-line 1)))
            (when found
              (let* ((bol (line-beginning-position))
                     (eol (line-beginning-position 2))
                     ;; Line format is "  X path": path starts at column 4.
                     (path-start (min eol (+ bol 4)))
                     (line-ov (make-overlay bol eol))
                     (mark-ov (make-overlay bol (min eol (+ bol 2))))
                     (path-ov (make-overlay path-start eol)))
                (overlay-put line-ov 'face 'diffview-current-entry)
                (overlay-put mark-ov 'display
                             (propertize "▶ " 'face 'diffview-current-marker))
                (overlay-put path-ov 'face 'diffview-current-marker)
                (setq diffview--current-ovs
                      (list line-ov mark-ov path-ov))))))))))

(defun diffview--render (buffer entries)
  "Render ENTRIES into BUFFER and set the session's `diffview--entries'."
  (setq diffview--entries entries)
  (with-current-buffer buffer
    (let ((inhibit-read-only t))
      (erase-buffer)
      (dolist (section diffview--sections)
        (let* ((sym (car section))
               (label (cdr section))
               (group (seq-filter
                       (lambda (e) (eq (plist-get e :section) sym)) entries)))
          (when group
            (insert (propertize (format "%s (%d)\n" label (length group))
                                'face 'diffview-section-heading))
            (dolist (e group)
              (let ((start (point))
                    (st (plist-get e :status)))
                (insert "  "
                        (propertize st 'face (diffview--status-face st))
                        " " (plist-get e :path) "\n")
                (put-text-property start (point) 'diffview-entry e)))
            (insert "\n"))))
      (goto-char (point-min)))))

(defun diffview--entry-at-point ()
  "Return the entry plist on the current panel line, or nil.
Falls back to the session's current entry when point is off any line."
  (or (get-text-property (point) 'diffview-entry)
      (and diffview--entries (nth diffview--current-index diffview--entries))))

(defun diffview--goto-index (i)
  "Move panel point to the line of the Ith entry, if resolvable.
Uses the `*diffview*' window when present, else the current buffer."
  (let* ((entry (nth i diffview--entries))
         (win (get-buffer-window "*diffview*")))
    (when entry
      (if win
          (with-selected-window win (diffview--goto-entry-line entry))
        (diffview--goto-entry-line entry))))
  (diffview--update-current-highlight))

(defun diffview--goto-entry-line (entry)
  "Move point in the current buffer to ENTRY's line."
  (goto-char (point-min))
  (let (found)
    (while (and (not found) (not (eobp)))
      (if (eq (get-text-property (point) 'diffview-entry) entry)
          (setq found t)
        (forward-line 1)))
    (when found (beginning-of-line))))

;;;; Diff pane --------------------------------------------------------

(declare-function diffview-viewer-mode "diffview")

(defun diffview--rev-buffer (rev path)
  "Return a read-only buffer holding PATH at git REV.
REV \"\" means the index entry (:PATH); otherwise REV:PATH (e.g. HEAD)."
  (let* ((spec (if (string-empty-p rev) (concat ":" path) (concat rev ":" path)))
         (tag  (if (string-empty-p rev) "index" rev))
         (buf  (get-buffer-create (format " *diffview:%s:%s*" tag path))))
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            (default-directory (or diffview--root default-directory)))
        (erase-buffer)
        ;; The object may not exist (e.g. HEAD:PATH for an added file, or
        ;; :PATH for a staged deletion) — treat that as empty, don't error.
        (ignore-errors (magit-git-insert "show" spec))
        (goto-char (point-min)))
      ;; Syntax highlight as PATH's type without actually visiting a file.
      (let ((buffer-file-name path))
        (delay-mode-hooks (set-auto-mode)))
      (setq buffer-read-only t))
    buf))

(defun diffview--empty-buffer (path)
  "Return a per-PATH empty buffer (the base for an untracked file)."
  (get-buffer-create (format " *diffview:empty:%s*" path)))

(defun diffview--work-buffer (path)
  "Return a read-only snapshot buffer of PATH's working-tree contents.
We deliberately do NOT use the live file buffer (`find-file-noselect'):
vdiff's scroll-lock silently fails to sync when one pane is a file-visiting
buffer, leaving the two sides out of step.  A plain temp buffer syncs
correctly, and since diffview is a review view (staging is file-level from
the panel) a read-only snapshot is the right model.  `R' refreshes it."
  (let ((buf (get-buffer-create (format " *diffview:work:%s*" path)))
        (abs (expand-file-name path diffview--root)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        ;; A deleted (or renamed-away) entry has no working-tree file — leave the
        ;; buffer empty so vdiff shows an all-removed diff instead of erroring.
        (when (file-readable-p abs)
          (insert-file-contents abs))
        (goto-char (point-min)))
      (let ((buffer-file-name path))
        (delay-mode-hooks (set-auto-mode)))
      (setq buffer-read-only t))
    buf))

(defun diffview--diff-buffers (section path)
  "Return (LEFT . RIGHT) version buffers for PATH in SECTION.
LEFT = old/base, RIGHT = new/current."
  (pcase section
    ('unstaged  (cons (diffview--rev-buffer "" path)        ; index
                      (diffview--work-buffer path)))         ; working tree
    ('staged    (cons (diffview--rev-buffer "HEAD" path)    ; HEAD
                      (diffview--rev-buffer "" path)))       ; index
    ('untracked (cons (diffview--empty-buffer path)
                      (diffview--work-buffer path)))))       ; working tree

(defun diffview--main-window ()
  "Return a live window that is not the panel side-window."
  (or (seq-find (lambda (w)
                  (and (not (window-parameter w 'window-side))
                       (not (eq (window-buffer w) (get-buffer "*diffview*")))))
                (window-list))
      (selected-window)))

(defun diffview--quit-vdiff-sessions ()
  "Quit every live vdiff session and strip `diffview-viewer-mode'.
Also strips the viewer mode so its TAB/q/hunk bindings don't linger.
`inhibit-message'/`message-log-max' hush vdiff's per-cycle \"vdiff exited\"
and \"Truncate long lines disabled\" chatter.  Guarded against buffers that
an earlier `vdiff-quit' kills mid-iteration."
  (let ((inhibit-message t) (message-log-max nil))
    (dolist (b (buffer-list))
      (when (buffer-live-p b)
        (ignore-errors
          (with-current-buffer b
            (when (bound-and-true-p vdiff-mode)
              (vdiff-quit))
            (when (bound-and-true-p diffview-viewer-mode)
              (diffview-viewer-mode -1))))))))

(defun diffview--main-windows ()
  "Return the live non-side windows on the selected frame."
  (seq-remove (lambda (w) (window-parameter w 'window-side))
              (window-list nil 'no-minibuf)))

(defun diffview--collapse-main-windows ()
  "Reduce the main (non-side) area to a single window, keeping side windows.
Deliberately uses `delete-window' rather than `delete-other-windows':
in this Emacs the latter deletes the panel side-window too, which would
destroy the diffview panel."
  (dolist (w (cdr (diffview--main-windows)))
    (when (window-live-p w) (delete-window w))))

(defun diffview--vdiff-layout (buffer-a buffer-b &optional _rotate)
  "A vdiff 2-way layout that splits the selected window in place.
Unlike `vdiff-2way-layout-function-default' it never calls
`delete-other-windows', so the diffview panel side-window survives."
  (switch-to-buffer buffer-a)
  (set-window-buffer (split-window-horizontally) buffer-b))

(defun diffview--show-diff (entry)
  "Show ENTRY's side-by-side diff in the main window area via vdiff."
  (unless (featurep 'vdiff)
    (user-error "vdiff is not installed — rebuild your Emacs config"))
  ;; Tear down the previous side-by-side before building the next, so we never
  ;; leave `vdiff-mode' (with its hooks/overlays) on the user's file buffers or
  ;; accumulate orphaned sessions while cycling files.
  (diffview--quit-vdiff-sessions)
  (let* ((path (plist-get entry :path))
         (pair (diffview--diff-buffers (plist-get entry :section) path))
         (left (car pair))
         (right (cdr pair)))
    ;; Collapse the main area to one window (keeping the panel side-window),
    ;; then let our custom layout split just that window.  We must avoid
    ;; `delete-other-windows' entirely — it removes side windows here.
    (diffview--collapse-main-windows)
    (with-selected-window (diffview--main-window)
      (let ((vdiff-2way-layout-function #'diffview--vdiff-layout)
            (inhibit-message t) (message-log-max nil)) ; hush vdiff newline warnings
        (vdiff-buffers left right)))
    (dolist (b (list left right))
      (when (buffer-live-p b)
        (with-current-buffer b (diffview-viewer-mode 1))))
    ;; `vdiff-buffers' kicks off its diff *asynchronously*, and on our content
    ;; that sentinel errors ("number-or-marker-p, nil") and leaves the
    ;; line-translation map empty — so scroll-lock has nothing to sync.  Defuse
    ;; that async process (neutralize its sentinel so it can't error when we kill
    ;; it), then force a *synchronous* refresh (vdiff's testing path uses
    ;; `call-process' + the sync sentinel) so the map is populated
    ;; deterministically before the user can scroll.  `inhibit-message' hides
    ;; vdiff's harmless "does not end in a newline" chatter.
    (when (buffer-live-p left)
      (with-current-buffer left
        (when (bound-and-true-p vdiff--session)
          (let ((proc (get-buffer-process
                       (vdiff-session-process-buffer vdiff--session))))
            (when (process-live-p proc)
              (set-process-sentinel proc #'ignore))))
        (let ((vdiff--testing-mode t)
              (inhibit-message t) (message-log-max nil))
          (vdiff-refresh))))))

;;;; Session commands -------------------------------------------------

;;;###autoload
(defun diffview-open ()
  "Open the diffview panel + side-by-side diff for the current repo."
  (interactive)
  (let ((root (magit-toplevel)))
    (unless root (user-error "Not inside a Git repository"))
    (setq diffview--root root)
    (let ((entries (diffview--collect-entries)))
      (unless entries (user-error "No changes to show"))
      (setq diffview--saved-window-config (current-window-configuration)
            diffview--current-index 0)
      (let ((buf (get-buffer-create "*diffview*")))
        (with-current-buffer buf
          (unless (derived-mode-p 'diffview-panel-mode) (diffview-panel-mode))
          ;; Anchor panel-invoked commands (stage/unstage/refresh) to the repo.
          (setq default-directory root))
        (diffview--render buf entries)
        (display-buffer-in-side-window
         buf '((side . left) (slot . 0) (window-width . 40)))
        (diffview--show-diff (nth 0 entries))
        (diffview--goto-index 0)
        (when (window-live-p (get-buffer-window buf))
          (select-window (get-buffer-window buf)))))))

(defun diffview--kill-temp-buffers ()
  "Kill the transient ` *diffview:…*' version buffers."
  (dolist (b (buffer-list))
    (when (string-prefix-p " *diffview:" (buffer-name b))
      (kill-buffer b))))

(defun diffview-close ()
  "Close the diffview session and restore the previous layout."
  (interactive)
  ;; Quit any live vdiff session (guarded against buffers killed mid-teardown).
  (diffview--quit-vdiff-sessions)
  (diffview--kill-temp-buffers)
  (when-let ((w (get-buffer-window "*diffview*"))) (delete-window w))
  (when-let ((b (get-buffer "*diffview*"))) (kill-buffer b))
  (setq diffview--entries nil diffview--current-index 0)
  (when diffview--saved-window-config
    (set-window-configuration diffview--saved-window-config)
    (setq diffview--saved-window-config nil)))

;;;; Navigation -------------------------------------------------------

(defun diffview--focus-side ()
  "Which diffview window is selected: `panel', `left', `right', or nil."
  (let ((name (buffer-name (window-buffer (selected-window)))))
    (cond ((equal name "*diffview*") 'panel)
          ((string-prefix-p " *diffview:work:" name) 'right)
          ((string-prefix-p " *diffview:" name) 'left)
          (t nil))))

(defun diffview--restore-focus (side)
  "Re-select the window for SIDE after the diff panes were rebuilt.
Keeps focus put across a file cycle instead of dumping it elsewhere."
  (let ((win (pcase side
               ('panel (get-buffer-window "*diffview*"))
               ('right (seq-find
                        (lambda (w) (string-prefix-p
                                     " *diffview:work:"
                                     (buffer-name (window-buffer w))))
                        (window-list)))
               ('left (seq-find
                       (lambda (w)
                         (let ((n (buffer-name (window-buffer w))))
                           (and (string-prefix-p " *diffview:" n)
                                (not (string-prefix-p " *diffview:work:" n)))))
                       (window-list)))
               (_ nil))))
    (when (window-live-p win) (select-window win))))

(defun diffview--select (index)
  "Make INDEX (wrapped) the current entry: move point + refresh diff.
Focus is kept on the same window role (panel/left/right) across the cycle."
  (when diffview--entries
    (let ((side (diffview--focus-side)))
      (setq diffview--current-index (mod index (length diffview--entries)))
      (diffview--goto-index diffview--current-index)
      (diffview--show-diff (nth diffview--current-index diffview--entries))
      (diffview--restore-focus side))))

(defun diffview-select-next-entry ()
  "Select the next file and show its diff (wraps)."
  (interactive)
  (diffview--select (1+ diffview--current-index)))

(defun diffview-select-prev-entry ()
  "Select the previous file and show its diff (wraps)."
  (interactive)
  (diffview--select (1- diffview--current-index)))

(defun diffview-open-entry ()
  "Show the diff for the entry on the current panel line."
  (interactive)
  (let ((entry (get-text-property (point) 'diffview-entry)))
    (when entry
      (let ((i (seq-position diffview--entries entry #'eq)))
        (when i (diffview--select i))))))

;;;; Staging / refresh ------------------------------------------------

(defun diffview--apply-stage (entry stage)
  "Stage (STAGE non-nil) or unstage ENTRY's path via magit."
  (let ((path (plist-get entry :path)))
    (if stage (magit-stage-files (list path)) (magit-unstage-files (list path)))))

(defun diffview-refresh ()
  "Recollect entries, rebuild the panel, and keep a sensible selection."
  (interactive)
  (let* ((buf (get-buffer "*diffview*"))
         (prev (and diffview--entries
                    (nth diffview--current-index diffview--entries)))
         (prev-path (and prev (plist-get prev :path)))
         (entries (and buf (let ((default-directory (or (magit-toplevel)
                                                        default-directory)))
                             (diffview--collect-entries)))))
    (when buf
      (if (null entries)
          (diffview-close)
        (diffview--render buf entries)
        (setq diffview--current-index
              (or (and prev-path
                       (seq-position
                        entries prev-path
                        (lambda (e p) (equal (plist-get e :path) p))))
                  (min diffview--current-index (1- (length entries)))))
        (diffview--goto-index diffview--current-index)
        (diffview--show-diff (nth diffview--current-index entries))))))

(defun diffview-stage-entry ()
  "Stage the file at point."
  (interactive)
  (when-let ((e (diffview--entry-at-point)))
    (diffview--apply-stage e t) (diffview-refresh)))

(defun diffview-unstage-entry ()
  "Unstage the file at point."
  (interactive)
  (when-let ((e (diffview--entry-at-point)))
    (diffview--apply-stage e nil) (diffview-refresh)))

(defun diffview-toggle-stage-entry ()
  "Toggle staged/unstaged for the file at point."
  (interactive)
  (when-let ((e (diffview--entry-at-point)))
    (diffview--apply-stage e (not (eq (plist-get e :section) 'staged)))
    (diffview-refresh)))

(defun diffview-stage-all ()
  "Stage all changes."
  (interactive)
  (magit-stage-modified t)
  (diffview-refresh))

(defun diffview-unstage-all ()
  "Unstage everything."
  (interactive)
  (magit-unstage-all)
  (diffview-refresh))

(defun diffview-restore-entry ()
  "Discard changes to the file at point (with confirmation)."
  (interactive)
  (when-let ((e (diffview--entry-at-point)))
    (let ((path (plist-get e :path)))
      (when (yes-or-no-p (format "Discard changes to %s? " path))
        (if (eq (plist-get e :section) 'untracked)
            (delete-file path)
          (magit-run-git "checkout" "--" path))
        (diffview-refresh)))))

;;;; Viewer minor mode (active in the two vdiff buffers) --------------

(defvar diffview-viewer-mode-map (make-sparse-keymap)
  "Keymap for `diffview-viewer-mode' (evil bindings added later).")

(define-minor-mode diffview-viewer-mode
  "Minor mode enabled in diffview's side-by-side buffers.
Provides diffview-style hunk navigation and file cycling on top of vdiff."
  :lighter " DV"
  :keymap diffview-viewer-mode-map
  ;; evil activates a minor mode's `evil-define-key' bindings only after keymaps
  ;; are normalized.  That happens automatically for major modes, but a minor
  ;; mode toggled on an already-live buffer needs an explicit refresh — without
  ;; it our TAB/q/hunk bindings stay dormant and evil's defaults win.
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps))
  ;; Line numbers in the diff panes (`delay-mode-hooks' when building these
  ;; buffers skipped the usual text/prog-mode-hook, so enable explicitly).
  ;; Working (right) side gets relative/hybrid — natural for navigating the
  ;; buffer you're reviewing; the rev (index/HEAD, left) side gets absolute so
  ;; you can reference concrete line numbers in the base version.
  (cond (diffview-viewer-mode
         (setq-local display-line-numbers-type
                     (if (string-prefix-p " *diffview:work:" (buffer-name))
                         'relative t))
         (display-line-numbers-mode 1))
        (t (display-line-numbers-mode -1))))

;;;; Keybindings ------------------------------------------------------
;; Mode-local evil bindings, mirroring diffview.nvim.  evil is already
;; loaded (diffview loads after evil in init.el); the guard is harmless.

(with-eval-after-load 'evil
  (evil-define-key 'normal diffview-panel-mode-map
    ;; Bind both `<tab>' (GUI) and `TAB' (terminal, where Tab is C-i) so file
    ;; cycling works whether Emacs runs graphically or in `-nw'.
    (kbd "<tab>")     #'diffview-select-next-entry
    (kbd "TAB")       #'diffview-select-next-entry
    (kbd "<backtab>") #'diffview-select-prev-entry
    (kbd "RET")       #'diffview-open-entry
    (kbd "o")         #'diffview-open-entry
    (kbd "-")         #'diffview-toggle-stage-entry
    (kbd "s")         #'diffview-stage-entry
    (kbd "u")         #'diffview-unstage-entry
    (kbd "S")         #'diffview-stage-all
    (kbd "U")         #'diffview-unstage-all
    (kbd "X")         #'diffview-restore-entry
    (kbd "R")         #'diffview-refresh
    (kbd "g r")       #'diffview-refresh
    (kbd "q")         #'diffview-close)

  (evil-define-key 'normal diffview-viewer-mode-map
    (kbd "]c")        #'vdiff-next-hunk
    (kbd "[c")        #'vdiff-previous-hunk
    (kbd "<tab>")     #'diffview-select-next-entry
    (kbd "TAB")       #'diffview-select-next-entry
    (kbd "<backtab>") #'diffview-select-prev-entry
    (kbd "q")         #'diffview-close))

(provide 'diffview)
;;; diffview.el ends here
