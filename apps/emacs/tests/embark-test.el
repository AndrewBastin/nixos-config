;;; embark-test.el --- ERT tests for embark.el helpers  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

;; These load the REAL source files, so they must run inside the BUILT Emacs
;; (./result/bin/emacs), where embark/consult/vertico are on the load path —
;; same arrangement as tests/vc-test.el.  Under `emacs -Q' the top-level
;; `require' in embark.el fails outright.  See the Run command in Step 2.
;;
;; `package-initialize' is REQUIRED: under `-q --batch' the package autoloads
;; are not activated, so completion.el's top-level (vertico-mode 1) dies with
;; "void-function vertico-mode".  Normal interactive startup does this for us.
(package-initialize)

;; completion.el first: embark.el modifies `vertico-map', which completion.el
;; establishes.  Paths are absolutised — `load' does not resolve relative names
;; against `default-directory' when load-path is set explicitly, as it is in
;; this build.
(defvar embark-test--root (or (getenv "REPO") default-directory))
(load (expand-file-name "apps/emacs/emacs.d/lisp/completion.el" embark-test--root) nil t)
(load (expand-file-name "apps/emacs/emacs.d/lisp/embark.el" embark-test--root) nil t)

;; NOTE: the split-open actions in embark.el (my/embark-*-right / -below and the
;; two consult keymaps) manipulate real windows and jump to real match
;; positions, so they are exercised interactively (plan Task 5), not here.  The
;; batch-checkable invariant those actions depend on — the interactive/plain
;; split of the wrapper commands — is guarded by
;; `embark-test-split-wrapper-arity' below.

(ert-deftest embark-test-split-wrapper-arity ()
  "The split wrappers keep the shapes embark's dispatch depends on.
embark passes the target to a plain function but injects it into a command's
minibuffer prompt, so the *jumpers* must be non-interactive one-arg functions
and the *commands* must be zero-arg interactive commands.  Swap either and the
action silently misfires — the target is lost or the wrong dispatch path runs.
This is the load-bearing invariant flagged in the design; assert it so a future
edit to the generating macros can't quietly break it."
  (dolist (cmd '(my/embark-find-file-right my/embark-find-file-below
                 my/embark-switch-buffer-right my/embark-switch-buffer-below))
    (should (commandp cmd))
    (should (equal (func-arity (symbol-function cmd)) '(0 . 0))))
  (dolist (fn '(my/embark-goto-location-right my/embark-goto-location-below
                my/embark-goto-grep-right my/embark-goto-grep-below))
    (should-not (commandp fn))
    (should (equal (func-arity (symbol-function fn)) '(1 . 1)))))

;;; my/quickfix-open ------------------------------------------------------
;; keybindings.el needs evil loaded before it (it calls `evil-define-key' at
;; top level), so require it first — same pattern as vc-test.el requiring
;; ghostel up front.  Everything else it references (my/neotree-toggle,
;; eglot-…) appears only as a binding target, never called at load time, so
;; those staying undefined here is harmless.
(require 'evil)
(load (expand-file-name "apps/emacs/emacs.d/lisp/keybindings.el"
                        embark-test--root)
      nil t)

(ert-deftest embark-test-quickfix-open-pops-to-error-buffer ()
  "When an error list exists, pop to it."
  (let* ((target (generate-new-buffer "*test-grep*"))
         (popped nil))
    (unwind-protect
        (cl-letf (((symbol-function 'next-error-find-buffer)
                   (lambda (&rest _) target))
                  ((symbol-function 'pop-to-buffer)
                   (lambda (buf &rest _) (setq popped buf))))
          (my/quickfix-open)
          (should (eq popped target)))
      (kill-buffer target))))

(ert-deftest embark-test-quickfix-open-reports-when-absent ()
  "With no error list, report it rather than signalling.
`next-error-find-buffer' errors when nothing qualifies; SPC q q must not
propagate that as a stack trace."
  (let ((messaged nil))
    (cl-letf (((symbol-function 'next-error-find-buffer)
               (lambda (&rest _) (error "No buffers contain error message locations")))
              ((symbol-function 'pop-to-buffer)
               (lambda (&rest _) (error "should not be called")))
              ((symbol-function 'message)
               (lambda (fmt &rest args) (setq messaged (apply #'format fmt args)))))
      (my/quickfix-open)
      (should (equal messaged "No error list to open")))))

(ert-deftest embark-test-bracket-q-walks-the-error-list ()
  "]q and [q are bound to next-error / previous-error in evil normal state.
The leader keys SPC q q / SPC q l are covered separately by
`embark-test-leader-qq-and-ql-resolve' below."
  (should (eq (lookup-key evil-normal-state-map (kbd "]q")) #'next-error))
  (should (eq (lookup-key evil-normal-state-map (kbd "[q")) #'previous-error)))

(ert-deftest embark-test-bracket-d-still-bound ()
  "The pre-existing ]d/[d diagnostics motions survive the edit.
They are rewritten in the same `evil-define-key' form as ]q/[q, so a
mistake there would silently drop them."
  (should (eq (lookup-key evil-normal-state-map (kbd "]d"))
              #'flymake-goto-next-error))
  (should (eq (lookup-key evil-normal-state-map (kbd "[d"))
              #'flymake-goto-prev-error)))

(ert-deftest embark-test-leader-qq-and-ql-resolve ()
  "<leader>qq and <leader>ql resolve to their commands, in batch.
The task-4 brief claimed these were unverifiable outside an interactive
session, reasoning from `(kbd \"SPC q q\")': that literal spelling really
does return 1 from `lookup-key', because evil's SPC leader is a
`menu-item' wired up in `evil.el' (a module this harness never loads),
so \"1\" (\"needs more input\") is all you get.  But `(kbd \"<leader>qq\")'
is a different animal: `<leader>' is evil's own pseudo-key syntax, and
`kbd' turns it into the vector [leader ?q ?q].  `evil-define-key' binds
that vector straight into `evil-normal-state-map' — no menu-item, no
interactive dispatch involved — so `lookup-key' resolves it exactly as
written, even under `-batch'."
  (should (eq (lookup-key evil-normal-state-map (kbd "<leader>qq"))
              #'my/quickfix-open))
  (should (eq (lookup-key evil-normal-state-map (kbd "<leader>ql"))
              #'next-error-select-buffer)))

(ert-deftest embark-test-which-key-quickfix-group-label ()
  "The \"SPC q\" which-key group is labelled \"quickfix\".
`which-key-add-key-based-replacements' does not attach a label to qq/ql
individually; it pushes one regexp-based entry onto
`which-key-replacement-alist' per group, shaped like
  ((\"\\\\`SPC q\\\\'\" . nil) . (nil . \"quickfix\"))
\(see the function's body in which-key.el — Emacs 30.2's built-in
which-key, confirmed by loading it directly rather than guessing\).
Asserting on that exact shape, not merely that *some* entry survives,
is what makes this test fail if the \"SPC q\" \"quickfix\" line is ever
deleted from keybindings.el."
  (let ((entry (assoc (cons "\\`SPC q\\'" nil) which-key-replacement-alist)))
    (should entry)
    (should (equal (cdr entry) (cons nil "quickfix")))))

;;; embark-test.el ends here
