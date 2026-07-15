;;; vc-test.el --- ERT tests for vc.el dispatch  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
;; Load ghostel HERE, not lazily: `my/vc--jjui' does its own `(require 'ghostel)',
;; and that load would fset the real `ghostel-exec' over the `cl-letf' stub below
;; — so whichever jjui test ran first would spawn a real PTY and fail.  Requiring
;; it up front makes that `require' a no-op and the stubs order-independent.
(require 'ghostel)

;; vc.el does a load-time `(require 'vc-jj)' and `advice-add' on
;; `vc-jj-mode-line-string', so it must be loaded inside the BUILT Emacs
;; (./result/bin/emacs), where vc-jj is on the load path.  See the Run command
;; in Step 2.  `my/ml--jj-styled-changeid' is only a forward `declare-function'
;; here (used at call time, not load time), so no modeline stub is needed.
(load (expand-file-name "apps/emacs/emacs.d/lisp/vc.el"
                        (or (getenv "REPO") default-directory))
      nil t)

(defun vc-test--dispatch (jj-root)
  "Run `my/vc-status-dwim' with `.jj' probe forced to JJ-ROOT.
Return the porcelain called: `magit', or (jjui . ROOT) for the jj path."
  (let (called)
    (cl-letf (((symbol-function 'locate-dominating-file)
               (lambda (dir name)
                 (should (equal dir default-directory))
                 (when (equal name ".jj") jj-root)))
              ((symbol-function 'my/vc--jjui)
               (lambda (root) (setq called (cons 'jjui root))))
              ((symbol-function 'magit-status)
               (lambda (&rest _) (setq called 'magit))))
      (my/vc-status-dwim)
      called)))

(ert-deftest vc-test-status-dwim-jj ()
  "Inside a .jj tree, dispatch opens jjui on the jj root — not on `default-directory'."
  (should (equal (vc-test--dispatch "/repo/") '(jjui . "/repo/"))))

(ert-deftest vc-test-status-dwim-git ()
  "With no .jj ancestor, dispatch falls back to Magit."
  (should (eq (vc-test--dispatch nil) 'magit)))

(defun vc-test--jjui-buffer (root)
  "Run `my/vc--jjui' on ROOT with the spawn stubbed out; return its buffer.
The `ghostel-exec' stub calls `kill-all-local-variables' because the real one
switches the buffer to `ghostel-mode' — a major mode, so any buffer-local set
BEFORE it is wiped.  Without that, this test could not tell a working pin from
one installed too early."
  (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/usr/bin/jjui"))
            ((symbol-function 'pop-to-buffer) (lambda (buf &rest _) (set-buffer buf)))
            ((symbol-function 'ghostel-exec)
             (lambda (buffer &rest _)
               (with-current-buffer buffer (kill-all-local-variables)))))
    (my/vc--jjui root)))

(ert-deftest vc-test-jjui-buffer-name ()
  "The jjui terminal is named \"jjui: DIR\", with DIR abbreviated.
No \"term: \" prefix: that marks a shell terminal, and this buffer's major mode
already identifies it as a ghostel terminal."
  (let ((buf (vc-test--jjui-buffer "/tmp/repo/")))
    (unwind-protect
        (should (equal (buffer-name buf) "jjui: /tmp/repo"))
      (kill-buffer buf))))

(ert-deftest vc-test-jjui-name-pinned ()
  "The jjui buffer opts out of ghostel's title-driven renaming, buffer-locally.
jjui reports an OSC-2 title (\"jjui - <root>\"), and ghostel renames a terminal on
every title report; nil is `ghostel-buffer-name-function''s documented \"never
rename\" value.  Regression: the pin must outlive the `ghostel-mode' switch, and
must not leak to shell terminals, which should keep following their title/cwd."
  (let ((buf (vc-test--jjui-buffer "/tmp/repo/")))
    (unwind-protect
        (with-current-buffer buf
          (should (local-variable-p 'ghostel-buffer-name-function))
          (should (null ghostel-buffer-name-function))
          (should (default-value 'ghostel-buffer-name-function)))
      (kill-buffer buf))))

(ert-deftest vc-test-jjui-needs-executable ()
  "The jj path errors out cleanly when jjui is absent, rather than spawning a broken
terminal buffer.  Guards the `executable-find' check in `my/vc--jjui'."
  (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil)))
    (should-error (my/vc--jjui "/repo/") :type 'user-error)))

;;; vc-test.el ends here
