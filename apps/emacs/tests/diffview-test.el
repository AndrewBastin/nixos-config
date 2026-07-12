;;; diffview-test.el --- ERT tests for diffview.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'diffview)
;; diffview defers loading magit to `diffview-open'; the tests below call its
;; git plumbing (`magit-git-lines', `magit-staged-files', …) directly, so
;; load it explicitly.
(require 'magit)

(defvar diffview-test--counter 0
  "Monotonic counter for unique temp content (Math.random is unavailable).")

(defmacro diffview-test--with-repo (&rest body)
  "Run BODY inside a throwaway git repo bound as `default-directory'."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "diffview-test-" t))
          (default-directory (file-name-as-directory dir)))
     (unwind-protect
         (progn
           (call-process "git" nil nil nil "init" "-q")
           (call-process "git" nil nil nil "config" "user.email" "t@t")
           (call-process "git" nil nil nil "config" "user.name" "t")
           ,@body)
       (delete-directory dir t))))

(defun diffview-test--write (path content)
  "Write CONTENT to PATH under `default-directory'."
  (with-temp-file (expand-file-name path) (insert content)))

(defun diffview-test--git (&rest args)
  "Run git ARGS in `default-directory'."
  (apply #'call-process "git" nil nil nil args))

(ert-deftest diffview-test-collect-entries-sections ()
  (diffview-test--with-repo
    (diffview-test--write "committed.txt" "v1\n")
    (diffview-test--git "add" "committed.txt")
    (diffview-test--git "commit" "-qm" "init")
    ;; unstaged modification
    (diffview-test--write "committed.txt" "v2\n")
    ;; staged new file
    (diffview-test--write "staged.txt" "s\n")
    (diffview-test--git "add" "staged.txt")
    ;; untracked file
    (diffview-test--write "new.txt" "u\n")
    (let* ((entries (diffview--collect-entries))
           (sections (mapcar (lambda (e) (plist-get e :section)) entries)))
      ;; unstaged entries come before staged, staged before untracked
      (should (equal (sort (copy-sequence sections)
                           (lambda (a b)
                             (< (diffview--section-rank a)
                                (diffview--section-rank b))))
                     sections))
      (should (member '(:path "committed.txt" :status "M" :section unstaged)
                      (mapcar (lambda (e) (list :path (plist-get e :path)
                                                :status (plist-get e :status)
                                                :section (plist-get e :section)))
                              entries)))
      (should (seq-find (lambda (e) (and (equal (plist-get e :path) "staged.txt")
                                         (eq (plist-get e :section) 'staged)))
                        entries))
      (should (seq-find (lambda (e) (and (equal (plist-get e :path) "new.txt")
                                         (eq (plist-get e :section) 'untracked)))
                        entries)))))

(ert-deftest diffview-test-render-and-lookup ()
  (let ((entries (list (list :path "a.el" :status "M" :section 'unstaged)
                       (list :path "b.el" :status "A" :section 'staged)))
        (buf (get-buffer-create " *diffview-test-panel*")))
    (unwind-protect
        (progn
          (with-current-buffer buf (diffview-panel-mode))
          (diffview--render buf entries)
          (with-current-buffer buf
            (let ((text (buffer-string)))
              (should (string-match-p "Unstaged changes (1)" text))
              (should (string-match-p "Staged changes (1)" text))
              (should (string-match-p "M a\\.el" text))
              (should (string-match-p "A b\\.el" text)))
            ;; point on the first entry line resolves to that entry
            (diffview--goto-index 0)
            (should (equal (plist-get (diffview--entry-at-point) :path) "a.el"))
            (diffview--goto-index 1)
            (should (equal (plist-get (diffview--entry-at-point) :path) "b.el"))))
      (kill-buffer buf))))

(ert-deftest diffview-test-apply-stage ()
  (diffview-test--with-repo
    (diffview-test--write "committed.txt" "v1\n")
    (diffview-test--git "add" "committed.txt")
    (diffview-test--git "commit" "-qm" "init")
    (diffview-test--write "committed.txt" "v2\n")
    ;; Initially the change is unstaged.
    (should (member "committed.txt" (magit-unstaged-files)))
    (should-not (member "committed.txt" (magit-staged-files)))
    ;; Stage it.
    (diffview--apply-stage (list :path "committed.txt" :section 'unstaged) t)
    (should (member "committed.txt" (magit-staged-files)))
    (should-not (member "committed.txt" (magit-unstaged-files)))
    ;; Unstage it again.
    (diffview--apply-stage (list :path "committed.txt" :section 'staged) nil)
    (should (member "committed.txt" (magit-unstaged-files)))
    (should-not (member "committed.txt" (magit-staged-files)))))

;;; diffview-test.el ends here
