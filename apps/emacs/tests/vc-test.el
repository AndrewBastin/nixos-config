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

;; --- jjui -> Emacs diff bridge ------------------------------------------------

(ert-deftest vc-test-jjui-runs-emacs-wrapper ()
  "`SPC G G' spawns `jjui-emacs' (the wrapper carrying the Emacs-only jjui config),
never the stock `jjui' — that one must stay free of the Emacs key overrides."
  (let (program)
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/x"))
              ((symbol-function 'pop-to-buffer) (lambda (buf &rest _) (set-buffer buf)))
              ((symbol-function 'ghostel-exec)
               (lambda (_buffer prog &rest _) (setq program prog))))
      (kill-buffer (my/vc--jjui "/tmp/repo/")))
    (should (equal program "jjui-emacs"))))

(defmacro vc-test--with-jj-repo (&rest body)
  "Run BODY in a throwaway jj repo: c1 adds a.txt+b.txt, c2 edits a.txt, @ edits it again.
An empty $JJ_CONFIG keeps the user's config (watchman, signing, …) out of it."
  (declare (indent 0))
  ;; The temp dir is held in its OWN variable and deleted by that name — never
  ;; via `default-directory', which is buffer-local: BODY may leave another
  ;; buffer current, and cleanup would then recursively delete THAT buffer's
  ;; directory (it once took out the whole checkout the suite was run from).
  `(let* ((vc-test--dir (file-name-as-directory (make-temp-file "vc-test-jj" t)))
          (default-directory vc-test--dir)
          (process-environment
           (append (list (concat "JJ_CONFIG=" (make-temp-file "vc-test-jjcfg"))
                         "JJ_USER=t" "JJ_EMAIL=t@example.com")
                   process-environment)))
     (unwind-protect
         (cl-flet ((jj (&rest args)
                     (should (zerop (apply #'call-process "jj" nil nil nil args)))))
           (jj "git" "init")
           (write-region "one\n" nil "a.txt") (write-region "bee\n" nil "b.txt")
           (jj "commit" "-m" "c1")
           (write-region "two\n" nil "a.txt")
           (jj "commit" "-m" "c2")
           (write-region "three\n" nil "a.txt")
           ,@body)
       (delete-directory vc-test--dir t))))

(defun vc-test--jjui-diff-text (rev &optional file)
  "Text of the buffer `my/jjui-diff' shows for REV (and FILE) in the current repo."
  (let ((buf (my/jjui-diff default-directory rev file)))
    (unwind-protect
        (with-current-buffer buf
          (should (derived-mode-p 'diff-mode))
          (buffer-string))
      (kill-buffer buf))))

(ert-deftest vc-test-jjui-diff-revision ()
  "The diff buffer holds exactly the chosen revision's change — not its parent's,
not the working copy's."
  (vc-test--with-jj-repo
    (let ((text (vc-test--jjui-diff-text "description(substring:\"c2\")")))
      (should (string-match-p "^-one$" text))
      (should (string-match-p "^\\+two$" text))
      (should-not (string-match-p "three\\|bee" text)))))

(ert-deftest vc-test-jjui-diff-file ()
  "With FILE, the diff is limited to that file (the details-pane `d')."
  (vc-test--with-jj-repo
    (let ((text (vc-test--jjui-diff-text "description(substring:\"c1\")" "b.txt")))
      (should (string-match-p "^\\+bee$" text))
      (should-not (string-match-p "one" text)))))

(ert-deftest vc-test-jjui-diff-pins-change-id ()
  "jjui hands over the SHORTEST unique prefix (\"s\"), which stops being unique as
the repo grows — so the buffer stores an 8-char id, and `g' keeps working later."
  (vc-test--with-jj-repo
    (let ((buf (my/jjui-diff default-directory "description(substring:\"c2\")")))
      (unwind-protect
          (should (string-match-p "\\`[k-z]\\{8\\}\\'"
                                  (nth 1 (buffer-local-value 'diff-vc-revisions buf))))
        (kill-buffer buf)))))

(ert-deftest vc-test-jjui-find-file-old-revision ()
  "RET on a file of an old revision: a read-only buffer holding THAT revision's
content, in the file's own major mode — and nothing written into the repo, where
jj would snapshot a stray `a.txt.~REV~' straight into @."
  (vc-test--with-jj-repo
    (let* ((dir default-directory)
           (buf (my/jjui-find-file dir "description(substring:\"c2\")" "a.txt")))
      (unwind-protect
          (with-current-buffer buf
            (should (equal (buffer-string) "two\n"))
            (should buffer-read-only)
            (should (derived-mode-p 'text-mode))
            (should-not (directory-files dir nil "~\\'")))
        (kill-buffer buf)))))

(ert-deftest vc-test-jjui-find-file-working-copy ()
  "RET on a file of the working-copy revision visits the real, editable file."
  (vc-test--with-jj-repo
    (let* ((dir default-directory)
           (buf (my/jjui-find-file dir "@" "a.txt")))
      (unwind-protect
          (with-current-buffer buf
            (should (equal buffer-file-name (expand-file-name "a.txt" dir)))
            (should-not buffer-read-only))
        (kill-buffer buf)))))

(ert-deftest vc-test-jjui-find-file-deleted ()
  "RET on a file the revision DELETED is a clean `user-error' (jjui flashes it) —
not a cryptic jj exit status, and for the working copy not an empty new-file
buffer pretending the file exists."
  (vc-test--with-jj-repo
    (delete-file "b.txt")
    (should-error (my/jjui-find-file default-directory "@" "b.txt") :type 'user-error)
    (should-not (get-buffer "b.txt"))
    (should (zerop (call-process "jj" nil nil nil "new")))
    (should-error (my/jjui-find-file default-directory "@-" "b.txt") :type 'user-error)))

;;; vc-test.el ends here
