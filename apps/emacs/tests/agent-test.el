;;; agent-test.el --- ERT tests for agent.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'flymake)

;; agent.el only touches my/frame-set-urgency at runtime (guarded), but stub it
;; anyway so my/agent-notify is exercised fully in batch.
(defvar agent-test--urgency-calls 0)
(unless (fboundp 'my/frame-set-urgency)
  (defun my/frame-set-urgency (&optional _)
    (setq agent-test--urgency-calls (1+ agent-test--urgency-calls))))

(load (expand-file-name "apps/emacs/emacs.d/lisp/agent.el"
                        (or (getenv "REPO") default-directory))
      nil t)

(ert-deftest agent-test-open-shows-file-without-focus ()
  "my/agent-open displays FILE at LINE in another window, focus unchanged."
  (let ((file (make-temp-file "agent" nil ".txt" "one\ntwo\nthree\nfour\n"))
        (before (selected-window)))
    (unwind-protect
        (let ((shown (my/agent-open file 3)))
          (should (equal shown (file-name-nondirectory file)))
          (let* ((buf (get-file-buffer file))
                 (win (get-buffer-window buf)))
            (should buf)
            (should win)
            (should (eq (selected-window) before))
            (should (= 3 (with-current-buffer buf
                           (line-number-at-pos (window-point win)))))))
      (when-let* ((b (get-file-buffer file))) (kill-buffer b))
      (delete-file file))))

(ert-deftest agent-test-diagnostics-not-open ()
  "Unopened file yields an explanatory string, not nil/empty."
  (let ((answer (my/agent-diagnostics "/nonexistent/never-opened.rs")))
    (should (stringp answer))
    (should (string-match-p "not open" answer))))

(ert-deftest agent-test-diagnostics-rows ()
  "Open buffer with flymake yields (LINE COL SEVERITY MESSAGE) rows."
  (let ((file (make-temp-file "agent" nil ".txt" "aaa\nbbbb\n")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (setq-local flymake-mode t)   ; pretend flymake is active
          (let ((diag (flymake-make-diagnostic
                       (current-buffer) 6 8 :warning "odd bs")))
            (cl-letf (((symbol-function 'flymake-diagnostics)
                       (lambda (&rest _) (list diag))))
              (should (equal (my/agent-diagnostics file)
                             '((2 1 :warning "odd bs")))))))
      (when-let* ((b (get-file-buffer file))) (kill-buffer b))
      (delete-file file))))

(ert-deftest agent-test-context-reports-focused-buffer ()
  "my/agent-context reports file, line and modified buffers."
  (let ((file (make-temp-file "agent" nil ".txt" "l1\nl2\nl3\n")))
    (unwind-protect
        (progn
          (set-window-buffer (selected-window) (find-file-noselect file))
          (with-selected-window (selected-window)
            (goto-char (point-min)) (forward-line 1)
            (set-window-point (selected-window) (point)))
          (let ((ctx (my/agent-context)))
            (should (equal (plist-get ctx :file) file))
            (should (= (plist-get ctx :line) 2))
            (should-not (plist-get ctx :region))
            (should-not (member file (plist-get ctx :modified)))
            (with-current-buffer (get-file-buffer file)
              (insert "dirty"))
            (should (member file (plist-get (my/agent-context) :modified)))))
      (when-let* ((b (get-file-buffer file)))
        (with-current-buffer b (set-buffer-modified-p nil))
        (kill-buffer b))
      (delete-file file))))

(ert-deftest agent-test-notify ()
  "my/agent-notify echoes with the [agent] prefix and flags urgency.
`current-message' is unusable in batch (echo area never populated), so
capture the `message' call instead."
  (setq agent-test--urgency-calls 0)
  (let (logged)
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (setq logged (apply #'format fmt args)))))
      (should (eq t (my/agent-notify "done"))))
    (should (equal logged "[agent] done")))
  (should (= 1 agent-test--urgency-calls)))

(ert-deftest agent-test-briefing-covers-registry ()
  "Briefing names every registered command, the socket, and stays short."
  (let ((text (my/agent-briefing)))
    (dolist (cmd my/agent-commands)
      (should (string-match-p (regexp-quote (symbol-name cmd)) text)))
    (should (string-match-p "emacsclient" text))
    (should (string-match-p "EMACS_SOCKET_NAME" text))
    (should (< (length text) 1500))))

(ert-deftest agent-test-shim-snippet ()
  "Wrapper snippet defines claude(), injects the briefing, avoids recursion."
  (let ((snip (my/agent-shim-snippet)))
    (should (string-match-p "^claude() {" snip))
    (should (string-match-p "command claude --append-system-prompt " snip))
    (should (string-match-p "\"\\$@\"" snip))
    ;; The briefing rides inside one shell-quoted argument: zsh single-quoting
    ;; must survive quotes/newlines in the text (shell-quote-argument's job).
    (should (string-match-p (regexp-quote (shell-quote-argument (my/agent-briefing)))
                            snip))))

;;; agent-test.el ends here
