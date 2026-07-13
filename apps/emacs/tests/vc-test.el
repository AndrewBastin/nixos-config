;;; vc-test.el --- ERT tests for vc.el dispatch  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

;; vc.el does a load-time `(require 'vc-jj)' and `advice-add' on
;; `vc-jj-mode-line-string', so it must be loaded inside the BUILT Emacs
;; (./result/bin/emacs), where vc-jj is on the load path.  See the Run command
;; in Step 2.  `my/ml--jj-styled-changeid' is only a forward `declare-function'
;; here (used at call time, not load time), so no modeline stub is needed.
(load (expand-file-name "apps/emacs/emacs.d/lisp/vc.el"
                        (or (getenv "REPO") default-directory))
      nil t)

(defun vc-test--dispatch (jj-root)
  "Run `my/vc-status-dwim' with `.jj' probe forced to JJ-ROOT; return the porcelain called."
  (let (called)
    (cl-letf (((symbol-function 'locate-dominating-file)
               (lambda (dir name)
                 (should (equal dir default-directory))
                 (when (equal name ".jj") jj-root)))
              ((symbol-function 'majutsu)
               (lambda (&rest _) (setq called 'majutsu)))
              ((symbol-function 'magit-status)
               (lambda (&rest _) (setq called 'magit))))
      (my/vc-status-dwim)
      called)))

(ert-deftest vc-test-status-dwim-jj ()
  "Inside a .jj tree, dispatch opens Majutsu."
  (should (eq (vc-test--dispatch "/repo/") 'majutsu)))

(ert-deftest vc-test-status-dwim-git ()
  "With no .jj ancestor, dispatch falls back to Magit."
  (should (eq (vc-test--dispatch nil) 'magit)))

(ert-deftest vc-test-majutsu-callable ()
  "Loading vc.el makes `majutsu' callable, so the jj path is not `void-function'.
Regression: `trivialBuild' ships no autoloads and nothing else requires majutsu;
vc.el must declare the autoload itself.  This test loads no stub for `majutsu'."
  (should (fboundp 'majutsu)))

;;; vc-test.el ends here
