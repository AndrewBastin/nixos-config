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

;; --- Mode-line change-id styling ------------------------------------------
;; vc-jj's own `vc-jj-mode-line-string' shows `change_id.shortest()' — the bare
;; shortest unique prefix, in one color.  I want it to read like `jj log': the
;; full 8-char change-id with its unique prefix highlighted and the rest in the
;; normal color.  jj templates expose exactly that split — `.shortest(8).prefix()'
;; (the unique bit) and `.shortest(8).rest()' (the padding) — so we override the
;; backend's mode-line function to fetch both and style them via
;; `my/ml--jj-styled-changeid' (defined in modeline.el, loaded right after this).
;;
;; `:around' (not `:override') so ANY failure — jj erroring, unexpected output —
;; falls back to vc-jj's stock string and the mode line always renders.  We reuse
;; vc-jj's own `vc-jj--process-lines' (which discards stderr, so jj's snapshot
;; warnings can't corrupt the fields) and `vc-jj-root'.
(defun my/vc-jj--mode-line-string (orig-fn file)
  "Around-advice for `vc-jj-mode-line-string' rendering FILE's jj change-id.
Return \"JJ<state>\" followed by the 8-char change-id with its shortest unique
prefix highlighted (`my/ml-jj-change-unique'), like `jj log'.  On any error, or
empty jj output, fall back to ORIG-FN so the mode line always renders."
  (condition-case nil
      (let* ((default-directory (vc-jj-root file))
             (out (vc-jj--process-lines
                   "log" "--no-graph" "-r" "@" "-T"
                   (concat "change_id.shortest(8).prefix() ++ \"\\n\" ++ "
                           "change_id.shortest(8).rest() ++ \"\\n\" ++ "
                           "change_id ++ \"\\n\" ++ "
                           "description.first_line()")))
             (prefix  (nth 0 out))
             (rest    (or (nth 1 out) ""))
             (longrev (or (nth 2 out) ""))
             (desc    (or (nth 3 out) ""))
             (def-ml  (vc-default-mode-line-string 'JJ file))
             (help-echo (get-text-property 0 'help-echo def-ml)))
        (if (not prefix)
            (funcall orig-fn file)          ; no jj output -> stock behavior
          (propertize
           ;; (substring def-ml 0 3) = "JJ" + the one-char state indicator, which
           ;; `my/ml--vc-format' strips back off; we keep it so vc-mode has the
           ;; usual "<Backend><state>" shape the segment parser expects.
           (concat (substring def-ml 0 3)
                   (my/ml--jj-styled-changeid prefix rest))
           'help-echo (concat help-echo "\nCurrent change: " longrev
                              (unless (string= desc "") (concat " (" desc ")"))))))
    (error (funcall orig-fn file))))

(advice-add 'vc-jj-mode-line-string :around #'my/vc-jj--mode-line-string)

;;; vc.el ends here
