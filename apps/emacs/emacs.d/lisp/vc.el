;;; vc.el --- Jujutsu (JJ) VC backend: registration + mode-line styling  -*- lexical-binding: t; -*-

;; Emacs' built-in VC only knows Git/Hg/… out of the box.  `vc-jj' adds a
;; Jujutsu backend, but registration is a LOAD-TIME side effect: requiring the
;; feature runs its top-level `(add-to-list 'vc-handled-backends 'JJ)', which —
;; because `add-to-list' prepends — lands JJ *ahead of* Git.  That ordering is
;; deliberate: this and many of my projects are colocated jj+git repos, and jj
;; parks git at a detached HEAD, so we want VC to try JJ first and report the jj
;; change-id (see `my/ml-vc-branch' in modeline.el) rather than a bare git hash.
(require 'vc-jj)

;; Defined in modeline.el (loaded by path right after this module); declared
;; here so byte-compiling vc.el on its own doesn't warn about the forward ref.
(declare-function my/ml--jj-styled-changeid "modeline" (prefix rest))

;; --- Directory-based VCS ref helpers --------------------------------------
;; Shared by the file-buffer mode-line advice (below) and the active-dir segment
;; in modeline.el.  Both take a DIRECTORY (no file needed) and shell out once.

(defun my/vc--jj-modeline-parts (dir)
  "Return (:id STYLED :help-echo TIP) for DIR's jj working-copy (@) change, or nil.
STYLED is the 8-char change-id with its shortest unique prefix highlighted
\(`my/ml--jj-styled-changeid'); TIP is the \"Current change: <full> (<desc>)\"
tooltip tail.  One `jj log' call; nil on any error or empty output.
`vc-jj--process-lines' discards stderr, so jj's snapshot warnings can't corrupt
the fields.  The leading nil is the FILE-OR-LIST arg of the current (codeberg
main) `(file-or-list &rest args)' signature — pass nil for repo-root-relative
runs like this one; the ELPA 0.5 signature had no such argument at all."
  (ignore-errors
    (let* ((default-directory dir)
           (out (vc-jj--process-lines
                 nil "log" "--no-graph" "-r" "@" "-T"
                 (concat "change_id.shortest(8).prefix() ++ \"\\n\" ++ "
                         "change_id.shortest(8).rest() ++ \"\\n\" ++ "
                         "change_id ++ \"\\n\" ++ "
                         "description.first_line()")))
           (prefix (nth 0 out)))
      (when prefix
        (let ((rest    (or (nth 1 out) ""))
              (longrev (or (nth 2 out) ""))
              (desc    (or (nth 3 out) "")))
          (list :id (my/ml--jj-styled-changeid prefix rest)
                :help-echo (concat "Current change: " longrev
                                   (unless (string= desc "")
                                     (concat " (" desc ")")))))))))

(defun my/vc--git-branch (dir)
  "Return DIR's current git branch name, the short commit hash if detached, or nil."
  (ignore-errors
    (let ((branch (car (process-lines "git" "-C" dir "branch" "--show-current"))))
      (if (and branch (not (string= branch "")))
          branch
        (car (process-lines "git" "-C" dir "rev-parse" "--short" "HEAD"))))))

;; --- File-buffer mode-line styling (vc-jj advice) -------------------------
;; vc-jj's own `vc-jj-mode-line-string' shows `change_id.shortest()' — the bare
;; shortest unique prefix, one color.  We show the full 8-char change-id with its
;; unique prefix highlighted, like `jj log', by reusing `my/vc--jj-modeline-parts'.
;; `:around' (not `:override') so ANY failure falls back to vc-jj's stock string
;; and the mode line always renders.
(defun my/vc-jj--mode-line-string (orig-fn file)
  "Around-advice for `vc-jj-mode-line-string' rendering FILE's jj change-id.
Return \"JJ<state>\" + the highlighted 8-char change-id, with vc-jj's tooltip plus
the change tail.  Fall back to ORIG-FN on any failure or empty jj output."
  (or (ignore-errors
        (when-let* ((parts  (my/vc--jj-modeline-parts (vc-jj-root file)))
                    (def-ml (vc-default-mode-line-string 'JJ file)))
          (propertize
           ;; (substring def-ml 0 3) = "JJ" + the one-char state indicator, which
           ;; `my/ml--vc-format' strips back off; kept so vc-mode has the usual
           ;; "<Backend><state>" shape the segment parser expects.
           (concat (substring def-ml 0 3) (plist-get parts :id))
           'help-echo (concat (get-text-property 0 'help-echo def-ml)
                              "\n" (plist-get parts :help-echo)))))
      (funcall orig-fn file)))

(advice-add 'vc-jj-mode-line-string :around #'my/vc-jj--mode-line-string)

;; --- Repo-aware status dispatch (SPC G G) ---------------------------------
;; One binding, two porcelains: jjui for jj, Magit for git.  `magit-status' is
;; autoloaded by magit's own package, so a `declare-function' (a compiler hint
;; only) is enough.
;;
;; jj gets the jjui TUI rather than an Elisp porcelain: it is the tool I already
;; reach for outside Emacs, so this keeps ONE jj UI to learn instead of two.
;; Running it inside a ghostel terminal (not an external window) is what makes it
;; feel native — `ghostel-pre-spawn-hook' points $EDITOR at this Emacs's own
;; emacsclient (see section 5 of ghostel.el), so describing a change from jjui
;; opens the `*.jjdescription' buffer right here, in a split below.
;;
;; `ghostel-exec' (vs. the interactive `ghostel') runs one program on the PTY
;; with no shell and no shell integration — argv is passed through, so nothing is
;; word-split, and quitting jjui ends the process, which kills the buffer
;; (`ghostel-kill-buffer-on-exit').  It carries no autoload cookie, hence the
;; call-time `require'.
(declare-function magit-status "magit-status" (&optional directory cache))
(declare-function ghostel-exec "ghostel" (buffer program &optional args))

(defun my/vc--jjui (root)
  "Open jjui on the Jujutsu repo at ROOT, in a ghostel terminal in this window.
Always a fresh terminal: jjui is a transient view (`q' quits it and the buffer
goes with it), so there is nothing worth reusing, and no stale buffer to find.
Named \"jjui: DIR\" — not the \"term: …\" of a shell terminal (`my/ghostel-buffer-name'),
whose prefix is there to tell terminals apart from file buffers.  This buffer runs
ONE program that is named right there in the buffer name, and its major mode
already says it is a ghostel terminal."
  (unless (executable-find "jjui-emacs")
    (user-error "jjui-emacs not found in PATH"))
  (require 'ghostel)
  (let ((buffer (generate-new-buffer
                 (format "jjui: %s"
                         (abbreviate-file-name (directory-file-name root))))))
    (with-current-buffer buffer
      ;; `default-directory' is `permanent-local', so it survives the major-mode
      ;; switch inside `ghostel-exec' — unlike the rename pin below.
      (setq default-directory root))
    ;; Display BEFORE spawning: `ghostel-exec' sizes the PTY to the buffer's
    ;; window if it has one, and falls back to a fixed 80x24 if it does not.
    (pop-to-buffer buffer display-buffer--same-window-action)
    ;; `jjui-emacs', not `jjui': the wrapper from apps/emacs/default.nix that
    ;; points jjui at the Emacs-only config (apps/emacs/jjui/config.lua, the
    ;; jjui -> Emacs bridge below).  A `jjui' started any other way stays stock.
    (ghostel-exec buffer "jjui-emacs")
    ;; Keep the name we chose.  jjui reports an OSC-2 title ("jjui - <ROOT>",
    ;; always an unabbreviated absolute path), and ghostel renames a terminal to
    ;; match every title report — so without this the buffer turns into
    ;; "term: jjui - /home/andrew/nixos-config": the ~ lost, and back to the
    ;; "term: " prefix this deliberately drops.  nil is the documented
    ;; "never rename this buffer" value
    ;; of `ghostel-buffer-name-function'; buffer-local, so real shell terminals
    ;; still follow their title and cwd.
    ;;
    ;; This MUST run after `ghostel-exec': it switches the buffer to
    ;; `ghostel-mode', and a major mode runs `kill-all-local-variables', which
    ;; would silently drop the pin and let the rename through.
    (with-current-buffer buffer
      (setq-local ghostel-buffer-name-function nil))
    buffer))

(defun my/vc-status-dwim ()
  "Open jjui in a Jujutsu repo, else Magit.
Detection walks up from `default-directory' for a `.jj' directory, so it picks
jj even in the colocated jj+git repos here (where a `.git' also exists), and
jjui opens on the jj root it finds rather than on the subdirectory you called
it from."
  (interactive)
  (if-let* ((root (locate-dominating-file default-directory ".jj")))
      (my/vc--jjui (expand-file-name root))
    (magit-status)))

;; --- jjui -> Emacs bridge ---------------------------------------------------
;; Called BY jjui, not by me: apps/emacs/jjui/config.lua rebinds jjui's `d' to
;; `emacsclient -e (my/jjui-diff ROOT REV [FILE])', so a diff opens as a real
;; buffer here instead of in jjui's pager.  Only the jjui that `my/vc--jjui'
;; spawns loads that config.
;;
;; Runs `jj diff' itself rather than going through `vc-diff-internal': that one
;; drags in working-revision lookups and a `revert-buffer-function' that forgets
;; the buffer it was given.  `-r REV' (not `--from REV- --to REV') is what stays
;; correct on merge commits.
(defun my/jjui--resolve (root rev)
  "Resolve REV in the repo at ROOT to (ID . WORKING-COPY-P).
ID is an 8-char change id.  jjui passes the SHORTEST unique prefix (often one
letter): fine right now, but it names buffers \"vc.el.~s~\" and turns ambiguous
as the repo grows, which would break `g' in a diff buffer kept around."
  (let ((default-directory (file-name-as-directory root)))
    (with-temp-buffer
      (unless (zerop (process-file
                      "jj" nil '(t nil) nil "log" "--no-graph" "--color=never"
                      "-r" rev "-T"
                      "change_id.shortest(8) ++ \" \" ++ current_working_copy ++ \"\\n\""))
        (user-error "jj log -r %s failed" rev))
      (pcase (split-string (buffer-string) "\n" t)
        (`(,line) (pcase-let ((`(,id ,wc) (split-string line " ")))
                    (cons id (equal wc "true"))))
        (_ (user-error "%s is not exactly one revision" rev))))))

(defun my/jjui-diff (root rev &optional file)
  "Show the diff of jj revision REV in the repo at ROOT, in the other window.
With FILE (a path relative to ROOT), limit the diff to that file.  One buffer
per repo, reused; `revert-buffer' re-runs the diff.  Returns the buffer."
  (let* ((default-directory (file-name-as-directory root))
         (rev (car (my/jjui--resolve root rev)))
         (buffer (get-buffer-create
                  (format "*jj diff: %s*"
                          (abbreviate-file-name (directory-file-name root))))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        ;; stderr dropped: jj's snapshot warnings must not land in the diff.
        ;; `%S' quoting of FILE matches jj's fileset string-literal syntax.
        (unless (zerop (apply #'process-file "jj" nil '(t nil) nil
                              "diff" "--git" "--color=never" "-r" rev
                              (and file (list (format "root-file:%S" file)))))
          (user-error "jj diff -r %s failed" rev)))
      (diff-mode)
      (setq buffer-read-only t
            default-directory (file-name-as-directory root))
      ;; Lets diff-mode fetch either side from jj: hunk fontification, and
      ;; `C-u RET' to visit the pre-change version of the file.
      (setq-local diff-vc-backend 'JJ
                  diff-vc-revisions (list (concat rev "-") rev)
                  revert-buffer-function
                  (lambda (&rest _) (my/jjui-diff root rev file)))
      (goto-char (point-min)))
    (unless (eq (window-buffer) buffer)
      (pop-to-buffer buffer t))
    buffer))

(defun my/jjui-find-file (root rev file)
  "Visit FILE (relative to ROOT) as of jj revision REV, in the other window.
A read-only \"FILE.~ID~\" buffer in FILE's own major mode — except when REV is
the working copy, where the real, editable file is the useful thing to get.
Returns the buffer."
  (pcase-let* ((`(,id . ,working-copy) (my/jjui--resolve root rev))
               (path (expand-file-name file root))
               (buffer
                ;; A file the revision deleted is still listed in jjui's details
                ;; pane.  Say so, rather than open an empty new-file buffer (working
                ;; copy) or surface jj's bare exit status (old revision).
                (if working-copy
                    (if (file-exists-p path)
                        (find-file-noselect path)
                      (user-error "%s does not exist in the working copy" file))
                  ;; Without this, `vc-find-revision' WRITES \"FILE.~ID~\" next to
                  ;; FILE — inside the repo, where jj snapshots it into @.
                  (let ((vc-find-revision-no-save t))
                    (condition-case nil
                        (vc-find-revision path id 'JJ)
                      (error (user-error "%s does not exist at %s" file id)))))))
    (pop-to-buffer buffer t)
    buffer))

;;; vc.el ends here
