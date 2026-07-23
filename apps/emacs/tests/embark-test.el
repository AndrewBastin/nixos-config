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

;;; embark-test.el ends here
