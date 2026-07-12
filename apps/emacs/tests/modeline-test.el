;;; modeline-test.el --- ERT tests for modeline.el VC segment  -*- lexical-binding: t; -*-

(require 'ert)
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

;;; modeline-test.el ends here
