;;; embark.el --- Embark actions, exports, and split-opening  -*- lexical-binding: t; -*-

;; Embark is the action layer over the vertico/consult stack in completion.el.
;; Two things it gives us:
;;
;;   `embark-act'    — a keymap of actions appropriate to the *type* of the
;;                     current target (file, buffer, grep match, symbol …), so
;;                     you can rename/delete/open-elsewhere without abandoning
;;                     the completion session you're in.
;;   `embark-export' — turn the whole session into a real buffer in the right
;;                     major mode.  This is the nvim quickfix list: a
;;                     consult-ripgrep session exports to `grep-mode', a
;;                     consult-line session to `occur-mode', and both implement
;;                     `next-error' — which is what ]q/[q drive (keybindings.el).
;;
;; NOTE: this file is named after the package it configures, which is safe only
;; because `lisp/' is never added to `load-path' (init.el loads modules by
;; absolute path).  Same arrangement as lisp/ghostel.el.

(require 'embark)
;; Must load after embark: embark-consult is the glue that registers the
;; exporters (`embark-exporters-alist') and consult's per-category default
;; actions (`embark-default-action-overrides').  It requires consult itself
;; at its own top level, so it's self-sufficient regardless of whether
;; consult has been loaded yet — no ordering dependency on completion.el here.
(require 'embark-consult)

;; Preview in collect buffers needs no setup here: embark-consult appends
;; `consult--default-completion-list-preview-setup' to `embark-collect-mode-hook'
;; itself.

;; The default `embark-mixed-indicator' shows a minimal hint, then after
;; `embark-mixed-indicator-delay' (0.5s) pops a verbose *Embark Actions* window
;; listing every binding.  That window steals layout mid-action.  which-key is
;; already the cheat-sheet mechanism in this config (keybindings.el sets it to
;; 0.3s), so use the compact indicator alone and let the keymap prompter's own
;; which-key-style display cover discovery.
(setq embark-indicators
      '(embark-minimal-indicator
        embark-highlight-indicator
        embark-isearch-highlight-indicator))

;; C-. acts, C-; runs the default action without showing the menu.  Global, so
;; they work on the thing at point in ordinary buffers too, not just candidates.
;; Safe here: this config is GUI-only (pgtk / macport), so there's no terminal
;; key-transmission problem with C-..
(keymap-global-set "C-." #'embark-act)
(keymap-global-set "C-;" #'embark-dwim)

;; Minibuffer keys.  vertico is already loaded (completion.el), so `vertico-map'
;; is bound and can be modified directly.
;;
;;   C-SPC  mark/unmark this candidate      (fzf-lua's <Tab>)
;;   C-,    act on every marked candidate
;;   C-l    export the session to a buffer  (fzf-lua's <C-q>)
;;
;; C-SPC rather than TAB deliberately: TAB stays `vertico-insert'.  C-l shadows
;; `recenter-top-bottom' only inside the minibuffer, where it was unbound.
(keymap-set vertico-map "C-SPC" #'embark-select)
(keymap-set vertico-map "C-,"   #'embark-act-all)
(keymap-set vertico-map "C-l"   #'embark-export)

;;; embark.el ends here
