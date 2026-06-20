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

;;; completion.el ends here
