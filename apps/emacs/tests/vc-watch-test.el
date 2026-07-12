;;; vc-watch-test.el --- ERT tests for vc-watch.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'vc)
(require 'vc-git)

;; vc-watch.el runs load-time `advice-add' on `my/neotree-follow' and an initial
;; `my/vc-watch-repoint'; provide the ghostel/modeline deps as stubs BEFORE load.
(unless (fboundp 'my/neotree-follow) (defun my/neotree-follow (&rest _) nil))
(defvar my/ml--active-vc-cache nil)
(unless (fboundp 'my/ml--active-vc) (defun my/ml--active-vc () nil))
(unless (fboundp 'my/ml--active-vc-invalidate)
  (defun my/ml--active-vc-invalidate () (setq my/ml--active-vc-cache nil)))
(load (expand-file-name "apps/emacs/emacs.d/lisp/vc-watch.el"
                        (or (getenv "REPO") default-directory))
      nil t)

(ert-deftest vc-watch-test-target-dir ()
  "Watch target is backend-specific; unknown backend -> nil."
  (should (equal (my/vc-watch--target-dir "/r/" 'JJ)
                 (expand-file-name ".jj/repo/op_heads/heads/" "/r/")))
  (should (equal (my/vc-watch--target-dir "/r/" 'Git)
                 (expand-file-name ".git/" "/r/")))
  (should-not (my/vc-watch--target-dir "/r/" 'Hg)))

(ert-deftest vc-watch-test-repoint-git ()
  "Repoint on a real git repo watches .git/, and is idempotent; teardown clears."
  (let ((repo (make-temp-file "vcw" t)))
    (unwind-protect
        (progn
          (call-process "git" nil nil nil "-C" repo "init" "-q")
          (cl-letf (((symbol-function 'my/active-dir)
                     (lambda () (file-name-as-directory repo))))
            (my/vc-watch-teardown)
            (my/vc-watch-repoint)
            (should my/vc-watch--descriptor)
            (should (equal my/vc-watch--watched-dir (expand-file-name ".git/" repo)))
            (let ((d my/vc-watch--descriptor))
              (my/vc-watch-repoint)          ; same target -> no-op
              (should (eq d my/vc-watch--descriptor)))
            (my/vc-watch-teardown)
            (should-not my/vc-watch--descriptor)))
      (delete-directory repo t))))

(ert-deftest vc-watch-test-refresh-repaints-only-on-change ()
  "`my/vc-watch--refresh' repaints only when the active-dir ref changed."
  (let ((paints 0) (val "aaa") (dir "/d/"))
    (cl-letf (((symbol-function 'my/ml--active-vc) (lambda () val))
              ((symbol-function 'my/active-dir) (lambda () dir))
              ((symbol-function 'force-mode-line-update)
               (lambda (&rest _) (setq paints (1+ paints)))))
      (setq my/ml--active-vc-cache (list (cons dir "aaa")))
      (my/vc-watch--refresh)               ; unchanged -> no paint
      (should (= paints 0))
      (setq my/ml--active-vc-cache (list (cons dir "aaa")) val "bbb")
      (my/vc-watch--refresh)               ; changed -> paint
      (should (= paints 1)))))

;;; vc-watch-test.el ends here
