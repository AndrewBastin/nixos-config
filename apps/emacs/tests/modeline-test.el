;;; modeline-test.el --- ERT tests for modeline.el VC segment  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
;; modeline.el has no `provide'; it is loaded by path on the command line
;; (see the Run command in Step 2) BEFORE this file, so its defuns are available.

;; Glyphs are built from hex codepoints, never written literally: literal
;; Nerd-Font chars get silently stripped when this file is written through
;; tooling.  #xe725 = nf-dev-git_branch, used for both git and jj (jj is told
;; apart by its change-id ref, not by a distinct glyph).
(defconst modeline-test--git-glyph (string #xe725))
(defconst modeline-test--jj-glyph  (string #xe725))

(ert-deftest modeline-test-git-branch ()
  "A git `vc-mode' string yields the branch glyph + branch name."
  (let ((out (my/ml--vc-format " Git-main")))
    (should (string-prefix-p modeline-test--git-glyph out))
    (should (string-suffix-p "main" out))))

(ert-deftest modeline-test-git-slashed-branch ()
  "Branch names with slashes and the `:' (modified) state char survive."
  (should (equal (my/ml--vc-format " Git:feature/x")
                 (concat modeline-test--git-glyph " feature/x"))))

(ert-deftest modeline-test-jj-change-id ()
  "A jj `vc-mode' string yields the branch glyph + the change-id ref."
  (let ((out (my/ml--vc-format " JJ@kx")))
    (should (string-prefix-p modeline-test--jj-glyph out))
    (should (string-suffix-p "kx" out))))

(ert-deftest modeline-test-unknown-backend-falls-back ()
  "An unrecognized backend falls back to the git branch glyph, ref preserved."
  (should (equal (my/ml--vc-format " Hg-tip")
                 (concat modeline-test--git-glyph " tip"))))

(ert-deftest modeline-test-nil-and-empty ()
  "Nil, non-strings, and refless strings return nil (non-VC buffers stay clean)."
  (should-not (my/ml--vc-format nil))
  (should-not (my/ml--vc-format 42))
  (should-not (my/ml--vc-format ""))
  (should-not (my/ml--vc-format "  ")))

(ert-deftest modeline-test-glyph-bytes-are-correct ()
  "Guards the strip-to-spaces bug: both git and jj emit the U+E725 branch glyph."
  (let ((git (my/ml--vc-format " Git-main"))
        (jj  (my/ml--vc-format " JJ@kx")))
    (should (equal (substring (encode-coding-string git 'utf-8) 0 3)
                   (unibyte-string #xee #x9c #xa5)))
    (should (equal (substring (encode-coding-string jj 'utf-8) 0 3)
                   (unibyte-string #xee #x9c #xa5)))))

(ert-deftest modeline-test-jj-styled-changeid ()
  "The change-id styler colors the unique PREFIX and leaves the REST plain."
  (let ((s (my/ml--jj-styled-changeid "ca" "c46683")))
    ;; `equal' compares string content, ignoring text properties.
    (should (equal s "cac46683"))
    ;; The two unique-prefix chars carry the highlight face...
    (should (eq (get-text-property 0 'face s) 'my/ml-jj-change-unique))
    (should (eq (get-text-property 1 'face s) 'my/ml-jj-change-unique))
    ;; ...and the rest has no face (inherits the normal mode-line color).
    (should (null (get-text-property 2 'face s)))
    (should (null (get-text-property 7 'face s)))))

(ert-deftest modeline-test-jj-styled-changeid-empty-rest ()
  "A fully-unique id (empty REST) still styles the whole prefix."
  (let ((s (my/ml--jj-styled-changeid "kxovlp" "")))
    (should (equal s "kxovlp"))
    (should (eq (get-text-property 0 'face s) 'my/ml-jj-change-unique))
    (should (eq (get-text-property 5 'face s) 'my/ml-jj-change-unique))))

(ert-deftest modeline-test-active-vc-jj ()
  "A JJ active dir yields the branch glyph + the styled change-id."
  (cl-letf (((symbol-function 'my/active-dir) (lambda () "/repo/"))
            ((symbol-function 'vc-responsible-backend) (lambda (&rest _) 'JJ))
            ((symbol-function 'my/vc--jj-modeline-parts)
             (lambda (_dir) (list :id (my/ml--jj-styled-changeid "ab" "cdef1234")))))
    (my/ml--active-vc-invalidate)
    (let ((out (my/ml--active-vc)))
      (should (string-prefix-p modeline-test--jj-glyph out))
      (should (string-suffix-p "abcdef1234" out)))))

(ert-deftest modeline-test-active-vc-git ()
  "A Git active dir yields the branch glyph + the branch name."
  (cl-letf (((symbol-function 'my/active-dir) (lambda () "/repo/"))
            ((symbol-function 'vc-responsible-backend) (lambda (&rest _) 'Git))
            ((symbol-function 'my/vc--git-branch) (lambda (_dir) "feature/x")))
    (my/ml--active-vc-invalidate)
    (should (equal (my/ml--active-vc)
                   (concat modeline-test--git-glyph " feature/x")))))

(ert-deftest modeline-test-active-vc-no-backend ()
  "No VC backend at the active dir yields nil."
  (cl-letf (((symbol-function 'my/active-dir) (lambda () "/tmp/plain/"))
            ((symbol-function 'vc-responsible-backend) (lambda (&rest _) nil)))
    (my/ml--active-vc-invalidate)
    (should-not (my/ml--active-vc))))

(ert-deftest modeline-test-active-vc-memoized ()
  "The memo returns the cached value; the backend is queried once per dir."
  (let ((calls 0))
    (cl-letf (((symbol-function 'my/active-dir) (lambda () "/repo/"))
              ((symbol-function 'vc-responsible-backend)
               (lambda (&rest _) (setq calls (1+ calls)) 'Git))
              ((symbol-function 'my/vc--git-branch) (lambda (_dir) "main")))
      (my/ml--active-vc-invalidate)
      (my/ml--active-vc)
      (my/ml--active-vc)
      (should (= calls 1)))))

(ert-deftest modeline-test-vc-branch-prefers-vc-mode ()
  "`my/ml-vc-branch' uses vc-mode when set, else falls back to the active dir."
  (cl-letf (((symbol-function 'my/active-dir) (lambda () "/repo/"))
            ((symbol-function 'vc-responsible-backend) (lambda (&rest _) 'Git))
            ((symbol-function 'my/vc--git-branch) (lambda (_dir) "adir")))
    (my/ml--active-vc-invalidate)
    (let ((vc-mode " Git-filebranch"))
      (should (string-suffix-p "filebranch" (my/ml-vc-branch))))
    (my/ml--active-vc-invalidate)
    (let ((vc-mode nil))
      (should (string-suffix-p "adir" (my/ml-vc-branch))))))

;;; modeline-test.el ends here
