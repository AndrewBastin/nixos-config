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

;; completion.el first: embark.el modifies `vertico-map' and its transformer is
;; tested against `my/consult-buffer-pair-with-mode', both of which live there.
;; Paths are absolutised — `load' does not resolve relative names against
;; `default-directory' when load-path is set explicitly, as it is in this build.
(defvar embark-test--root (or (getenv "REPO") default-directory))
(load (expand-file-name "apps/emacs/emacs.d/lisp/completion.el" embark-test--root) nil t)
(load (expand-file-name "apps/emacs/emacs.d/lisp/embark.el" embark-test--root) nil t)

(defun embark-test--candidate (name mode)
  "Build a consult-buffer candidate string the way completion.el does."
  (concat name (propertize (concat "  " mode) 'face 'completions-annotations)))

(ert-deftest embark-test-strip-annotation-removes-mode-suffix ()
  "The appended major-mode name is removed, leaving the bare buffer name."
  (should (equal (my/embark--strip-annotation
                  (embark-test--candidate "foo.el" "emacs-lisp-mode"))
                 "foo.el")))

(ert-deftest embark-test-strip-annotation-preserves-plain-string ()
  "A candidate with no annotation is returned unchanged.
Buffer candidates from sources other than `my/consult-buffer-pair-with-mode'
\(e.g. plain `switch-to-buffer') carry no annotation, and must survive intact."
  (should (equal (my/embark--strip-annotation "*scratch*") "*scratch*")))

(ert-deftest embark-test-strip-annotation-keeps-spaces-in-name ()
  "Only the faced run is stripped, not ordinary spaces in the buffer name.
Buffer names may legitimately contain spaces, so a naive split on \"  \"
would corrupt them."
  (should (equal (my/embark--strip-annotation
                  (embark-test--candidate "my notes.org" "org-mode"))
                 "my notes.org")))

(ert-deftest embark-test-buffer-target-strip-returns-type-cons ()
  "The transformer returns a (TYPE . STRIPPED) cons, as embark requires."
  (should (equal (my/embark-buffer-target-strip
                  'buffer (embark-test--candidate "foo.el" "emacs-lisp-mode"))
                 '(buffer . "foo.el"))))

(ert-deftest embark-test-transformer-is-registered ()
  "The transformer is installed for the `buffer' type."
  (should (eq (alist-get 'buffer embark-transformer-alist)
              #'my/embark-buffer-target-strip)))

(ert-deftest embark-test-real-candidate-round-trips-to-a-live-buffer ()
  "A candidate built by the REAL completion.el function strips to a live buffer.
This is the end-to-end guard: it catches drift between the face
`my/consult-buffer-pair-with-mode' applies and the face the transformer
trims, which no amount of synthetic-candidate testing would."
  (let* ((cand (car (my/consult-buffer-pair-with-mode
                     (get-buffer-create "*scratch*"))))
         (stripped (cdr (my/embark-buffer-target-strip 'buffer cand))))
    (should (equal stripped "*scratch*"))
    (should (bufferp (get-buffer stripped)))))

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
  "]q and [q are bound in evil normal state.
Only the bracket motions are checkable in batch; `<leader>' keys resolve
through evil's leader mechanism and `lookup-key' returns 1 for them, so
SPC q q / SPC q l are verified interactively instead."
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

;;; embark-test.el ends here
