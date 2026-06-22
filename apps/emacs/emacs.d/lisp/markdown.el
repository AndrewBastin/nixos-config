;;; markdown.el --- Markdown editing (GitHub-Flavored)  -*- lexical-binding: t; -*-

;; `markdown-mode' is already in the package set (apps/emacs/default.nix) so
;; eglot can render LSP hover docs via `gfm-view-mode'; here we turn it into a
;; real editing setup for Markdown files.  Loaded after `evil', so the markdown
;; bindings installed by `evil-collection-init' (RET to follow links, etc.) are
;; already in place.  No HTML preview is wired up: that needs an external
;; renderer bundled into the closure, which we deliberately skip — the preview/
;; export commands (`C-c C-c v', `markdown-live-preview-mode') will report a
;; missing `markdown-command' if invoked.

;; --- Open Markdown files in GitHub-Flavored mode --------------------------
;; markdown-mode autoloads `.md' -> `markdown-mode' into `auto-mode-alist' at
;; startup; we prefer `gfm-mode' (an autoloaded markdown-mode derivative): task-
;; list checkboxes (`[ ]'/`[x]'), strikethrough, and language-tagged fenced code
;; blocks, the way these files render on GitHub.  `add-to-list' prepends, and
;; `auto-mode-alist' is searched front-to-back, so our entries win over the
;; autoloaded markdown-mode ones.
(dolist (entry '(("\\.md\\'"       . gfm-mode)
                 ("\\.markdown\\'" . gfm-mode)))
  (add-to-list 'auto-mode-alist entry))

;; --- Editing behaviour ----------------------------------------------------
;; gfm-mode derives from markdown-mode, so these settings (and the hook below)
;; apply to both.
(with-eval-after-load 'markdown-mode
  ;; Fontify fenced code blocks with each language's real major mode (```rust …)
  ;; instead of one flat face — uses the tree-sitter/major modes already in the
  ;; package set.
  (setq markdown-fontify-code-blocks-natively t)
  ;; Render headers at graduated sizes (`#' largest) so document structure is
  ;; visible at a glance.
  (setq markdown-header-scaling t)
  ;; ATX headers as `### foo' with no trailing `###' — cleaner, and what GitHub
  ;; emits.
  (setq markdown-asymmetric-header t)
  ;; Indent nested list items by two columns on `M-RET'/list continuation.
  (setq markdown-list-indent-width 2))

;; --- Prose-friendly buffers -----------------------------------------------
;; Markdown is prose: soft-wrap long lines at the window edge (display only — no
;; newlines are inserted, so paragraphs stay one logical line) and move by visual
;; lines.
(add-hook 'markdown-mode-hook #'visual-line-mode)

;; --- Obsidian-style WYSIWYG: hide markup outside insert state -------------
;; markdown-mode can hide the syntax markup (emphasis `*'/`_', header `#',
;; `[text](url)' link plumbing) via `markdown-hide-markup'/`markdown-hide-urls',
;; leaving just the rendered text — bold shows bold, headers show big, a link
;; shows only its label.  We tie that to evil's editing state: normal/visual
;; (and every non-insert state) read as a clean rendered view, and entering
;; insert reveals the raw markdown so it can be edited, re-hiding on exit.
;;
;; `markdown-toggle-markup-hiding'/`-url-hiding' both set their variable AND
;; refontify the buffer, which is what actually applies/removes the invisibility;
;; just setting the variable wouldn't redraw.  They also `message' their new
;; state, so we bind `inhibit-message' — this fires on every insert↔normal
;; switch and the echo area shouldn't flash on each one.
;;
;; Caveat: hiding is buffer-wide, so insert reveals ALL markup at once (the whole
;; buffer reflows on the switch), not just the element at point like Obsidian.
(defun my/markdown-hide-markup (hide)
  "Hide markdown markup when HIDE is non-nil, else reveal it.
Toggles both markup and URL hiding together and refontifies, quietly."
  (let ((inhibit-message t)
        (arg (if hide 1 -1)))
    (markdown-toggle-markup-hiding arg)
    (markdown-toggle-url-hiding arg)))

(defun my/markdown-setup-wysiwyg ()
  "Start a markdown buffer in the hidden \"rendered\" view and wire evil state.
Insert state reveals the raw markup; leaving insert hides it again.  Hooks are
buffer-local so only markdown buffers are affected."
  (my/markdown-hide-markup t)
  (add-hook 'evil-insert-state-entry-hook
            (lambda () (my/markdown-hide-markup nil)) nil t)
  (add-hook 'evil-insert-state-exit-hook
            (lambda () (my/markdown-hide-markup t)) nil t))

(add-hook 'markdown-mode-hook #'my/markdown-setup-wysiwyg)

;;; markdown.el ends here
