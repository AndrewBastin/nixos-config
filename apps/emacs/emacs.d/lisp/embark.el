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

;;; Buffer candidates carry a major-mode suffix ----------------------------
;; `my/consult-buffer-pair-with-mode' (completion.el) appends the buffer's
;; major-mode name to the CANDIDATE STRING so the mode can be typed to filter.
;; consult itself is unaffected — it keeps the real buffer object alongside —
;; but embark acts on the string, so without this it would hand
;; `switch-to-buffer' "foo.el  emacs-lisp-mode" and every buffer action would
;; fail with "No buffer named …".
;;
;; The suffix is the only text in the candidate wearing the
;; `completions-annotations' face, so trimming from the first character with
;; that face recovers the bare name.  This is coupled to the face chosen in
;; completion.el — change it there and this stops trimming silently.
;;
;; Scoped to the `buffer' type only.  Candidates from other buffer sources
;; (plain `switch-to-buffer') have no faced run and pass through untouched.
(defun my/embark--strip-annotation (string)
  "Return STRING without a trailing `completions-annotations' run."
  (let ((pos (text-property-any 0 (length string)
                                'face 'completions-annotations string)))
    (if pos (substring string 0 pos) string)))

(defun my/embark-buffer-target-strip (type target)
  "Return (TYPE . TARGET) with TARGET's annotation suffix removed."
  (cons type (my/embark--strip-annotation target)))

(setf (alist-get 'buffer embark-transformer-alist)
      #'my/embark-buffer-target-strip)

;;; embark.el ends here
