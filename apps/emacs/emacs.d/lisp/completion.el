;;; completion.el --- Vertico/marginalia/orderless/consult completion UI  -*- lexical-binding: t; -*-

;; The fzf-lua equivalent from my Neovim config.
(vertico-mode 1)        ; show candidates as a vertical list in the minibuffer
(marginalia-mode 1)     ; annotate candidates (docstrings, file sizes, …)
;; `completion-styles' decides how typed text matches candidates.  `orderless'
;; = space-separated fuzzy terms in any order; `basic' keeps exact matching as a
;; fallback; files use `partial-completion' so "/u/s/b" expands to /usr/share/...
(setq completion-styles '(orderless basic)
      completion-category-overrides '((file (styles partial-completion))))

;;; completion.el ends here
