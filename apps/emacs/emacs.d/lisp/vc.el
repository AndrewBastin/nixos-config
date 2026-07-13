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
the fields."
  (ignore-errors
    (let* ((default-directory dir)
           (out (vc-jj--process-lines
                 "log" "--no-graph" "-r" "@" "-T"
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
;; One binding, two porcelains: Majutsu for jj, Magit for git.  `magit-status'
;; is autoloaded by magit's own package, so a `declare-function' (a compiler
;; hint only) is enough.  Majutsu is built via `trivialBuild' (see
;; apps/emacs/default.nix), which ships NO autoloads file, and nothing else
;; `require's it — so without help `majutsu' is `void-function' at call time.
;; Declare a real `autoload' for it: that both silences the byte-compiler AND
;; makes the command load on first use (so `M-x majutsu' works too).  Loading
;; majutsu.el after evil is already up (init.el load order) fires its own
;; `(with-eval-after-load 'evil (require 'majutsu-evil))', so `majutsu-evil-setup'
;; is defined by the time keybindings.el's after-load hook runs (Task 3).
(autoload 'majutsu "majutsu" "Open the Majutsu status/log buffer for the current jj repo." t)
(declare-function magit-status "magit-status" (&optional directory cache))

(defun my/vc-status-dwim ()
  "Open Majutsu in a Jujutsu repo, else Magit.
Detection walks up from `default-directory' for a `.jj' directory, so it picks
jj even in the colocated jj+git repos here (where a `.git' also exists)."
  (interactive)
  (if (locate-dominating-file default-directory ".jj")
      (majutsu)
    (magit-status)))

;;; vc.el ends here
