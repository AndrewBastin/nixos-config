;;; completion.el --- Vertico/marginalia/orderless/consult completion UI  -*- lexical-binding: t; -*-

;; The fzf-lua equivalent from my Neovim config.
(vertico-mode 1)        ; show candidates as a vertical list in the minibuffer
(marginalia-mode 1)     ; annotate candidates (docstrings, file sizes, …)
;; `completion-styles' decides how typed text matches candidates.  `orderless'
;; = space-separated fuzzy terms in any order; `basic' keeps exact matching as a
;; fallback; files use `partial-completion' so "/u/s/b" expands to /usr/share/...
(setq completion-styles '(orderless basic)
      completion-category-overrides '((file (styles partial-completion))))

;;; In-buffer completion popup at point (corfu) ------------------------------
;; corfu is vertico's sibling: it renders `completion-at-point' candidates in a
;; small popup at the cursor instead of the minibuffer.  eglot already supplies
;; the LSP candidates via its completion-at-point-function, so enabling
;; `global-corfu-mode' is enough to get IDE-style autocomplete in code buffers.
(require 'corfu)
(setq corfu-auto t          ; pop up automatically as you type, no C-M-i needed
      corfu-auto-prefix 2   ; …after this many characters
      corfu-auto-delay 0.1
      corfu-cycle t         ; wrap around when moving past the last candidate
      corfu-quit-no-match 'separator)
(global-corfu-mode 1)
;; Show documentation for the selected candidate in a side popup.
(require 'corfu-popupinfo)
(corfu-popupinfo-mode 1)

;;; cape: extra `completion-at-point' backends ------------------------------
;; eglot's CAPF only covers LSP buffers.  cape adds language-agnostic sources so
;; corfu still has candidates outside code (dabbrev = words from open buffers,
;; file = path completion).  They sit at the tail so LSP wins when available.
(require 'cape)
(add-to-list 'completion-at-point-functions #'cape-dabbrev t)
(add-to-list 'completion-at-point-functions #'cape-file t)

;;; consult-buffer: make the major mode searchable -------------------------
;; In `consult-buffer' (SPC b b) each candidate is a (STRING . BUFFER) pair:
;; STRING is what orderless matches *and* what's shown, while BUFFER (kept
;; aside) is what preview/switching use.  By default STRING is just the buffer
;; name, so the major mode — shown on the right by marginalia — can't be typed
;; to filter.  We swap in an `:as' that appends the mode name to STRING, so
;; typing e.g. "ghostel" narrows to ghostel-mode buffers.  BUFFER is untouched,
;; so switching and preview keep working.
(defun my/consult-buffer-pair-with-mode (buffer)
  "Return a (NAME+MODE . BUFFER) pair for `consult-buffer'.
Like `consult--buffer-pair', but the candidate string carries the buffer's
`major-mode' name (dimmed) so it can be matched when searching."
  (let ((name (buffer-name buffer))
        (mode (symbol-name (buffer-local-value 'major-mode buffer))))
    (cons (concat name
                  (propertize (concat "  " mode) 'face 'completions-annotations))
          buffer)))

(with-eval-after-load 'consult
  (setq consult-source-buffer
        (plist-put consult-source-buffer :items
                   (lambda () (consult--buffer-query
                               :sort 'visibility
                               :as #'my/consult-buffer-pair-with-mode))))
  (setq consult-source-project-buffer
        (plist-put consult-source-project-buffer :items
                   (lambda ()
                     (when-let* ((root (consult--project-root)))
                       (consult--buffer-query
                        :sort 'visibility :directory root
                        :as #'my/consult-buffer-pair-with-mode))))))

;; SPC b b shows a focused list — file buffers and terminals, but not the
;; *special* buffers (*Messages*, *scratch*, *Help*, compilation, …).  The full
;; list, special buffers included, stays on SPC b B (plain `consult-buffer').
;; Terminals are named after their cwd (no asterisks), so they survive this
;; filter; `consult-buffer-filter' excludes any buffer name it matches.
(defun my/consult-buffer-no-special ()
  "Like `consult-buffer', but hide \"*special*\" buffers (names matching ^*)."
  (interactive)
  (let ((consult-buffer-filter (cons "\\`\\*" consult-buffer-filter)))
    (consult-buffer)))

;;; completion.el ends here
