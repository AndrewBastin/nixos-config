;;; evil.el --- Evil mode, leader key, and escape-quits-everything  -*- lexical-binding: t; -*-

;; evil-collection requires `evil-want-keybinding' to be nil BEFORE evil loads,
;; so evil skips its own `evil-keybindings' and lets evil-collection own the
;; per-mode bindings.  Otherwise `evil-collection-init' (below) warns about the
;; conflicting bindings evil already installed.
(setq evil-want-keybinding nil)

;; Y yanks to end of line (nvim's default since 0.6), consistent with C and D.
;; Must also be set before evil loads — it decides Y's binding at define time.
(setq evil-want-Y-yank-to-eol t)

;; C-u scrolls half a page up in normal/visual/motion state (vim's default);
;; evil otherwise leaves it on Emacs's `universal-argument'.  Counts (10j) and
;; the minibuffer cover the prefix-arg uses.  Insert state is untouched (that
;; would be `evil-want-C-u-delete').  Read at load time by both evil and
;; evil-collection, so it too must be set before the requires.
(setq evil-want-C-u-scroll t)

(require 'evil)
(evil-mode 1)
(evil-set-undo-system 'undo-redo)

;; Use evil's own search (`evil-search') instead of Emacs isearch: search with
;; vim semantics — n/N keep direction, gn works, `:noh' clears highlighting,
;; and the full match set stays highlighted like nvim's hlsearch.
(evil-select-search-module 'evil-search-module 'evil-search)

;; Match nvim's opts (apps/nvim.nix): `splitright' — :vsplit / C-w v open to
;; the right — and `shiftwidth' 2, so >> / << shift by 2 columns instead of
;; evil's default 4.  (nvim doesn't set `splitbelow', so splits keep opening
;; above, matching vim's default there.)
(setq evil-vsplit-window-right t)
(setq-default evil-shift-width 2)

;; --- evil-collection --------------------------------------------------------
;; Vim-style bindings for all the special-mode buffers evil leaves alone
;; (magit, dired, help, eww, info, ibuffer, xref, …).  This is what makes
;; link/button following work the obvious way: `go' in *Help*, RET in
;; info/eww/markdown, etc.
;;
;; Leave the minibuffer alone — vertico/consult and our custom escape-quits
;; behaviour own it — by keeping `evil-collection-setup-minibuffer' at its
;; default nil.  Init runs here (before keybindings.el), so the hand-rolled
;; neotree/eglot bindings there load last and win on any overlap.
(require 'evil-collection)
(evil-collection-init)

;; --- nvim plugin equivalents -------------------------------------------------
;; nvim-surround -> evil-surround: ys{motion}{char} adds a surrounding pair,
;; cs{old}{new} changes it, ds{char} deletes it; S in visual state wraps.
(require 'evil-surround)
(global-evil-surround-mode 1)

;; mini.comment -> evil-commentary: gcc toggles a line comment, gc{motion} is
;; the comment operator (gc also works on a visual selection).  nvim binds
;; <leader>cc, but <leader>c is our code-action prefix (see keybindings.el),
;; so we use the standard vim-commentary keys instead.
(require 'evil-commentary)
(evil-commentary-mode 1)

;; vim's built-in C-a/C-x -> evil-numbers: increment/decrement the number at
;; point (evil doesn't implement these at all).  NOTE: this shadows the Emacs
;; C-x prefix in normal/visual state only; C-x commands still work from
;; insert/emacs state and the minibuffer.
(require 'evil-numbers)
(evil-define-key '(normal visual) 'global
  (kbd "C-a") #'evil-numbers/inc-at-pt
  (kbd "C-x") #'evil-numbers/dec-at-pt)

;; vim's bundled matchit -> evil-matchit: % also jumps between if/end, do/end
;; (elixir), def/end and HTML/JSX tag pairs, not just plain brackets.
(require 'evil-matchit)
(global-evil-matchit-mode 1)

;; nvim's native search count ([3/14] in the cmdline) -> evil-anzu: feeds
;; evil-search matches to anzu, which prepends "(3/14)" to the mode line while
;; a search is active.  The threshold caps the counting work in huge buffers.
(setq anzu-search-threshold 1000)
(require 'evil-anzu)

;; --- Leader key (SPC) -------------------------------------------------------
;; The leader is registered here; individual <leader>… bindings live in
;; keybindings.el (loaded later).
(evil-set-leader '(normal visual) (kbd "SPC"))

;; NOTE: no custom ESC handling here.  We rely on C-g (`keyboard-quit') as the
;; single universal cancel — aborting the minibuffer, closing *Completions*,
;; dismissing which-key/transient popups, etc.  In evil states ESC keeps its
;; native meaning (return to normal state / `evil-force-normal-state').

;;; evil.el ends here
