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
;;
;; Displaces the default `(buffer . embark--uniquify-orig-buffer)' (embark.el
;; line 212).  The default returns the `uniquify-orig-buffer' text property's
;; buffer-name when present, else the target unchanged.  Nothing sets that
;; property on Emacs 30.2: only producer is `project--read-project-buffer',
;; gated on `uniquify-get-unique-names' (absent here).  Even on Emacs 31, that
;; producer reads with category `project-buffer', not `buffer'.  Replacement is
;; safe; composing would guard a case nothing produces.
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

;;; Open a candidate in a split -------------------------------------------
;; fzf-lua parity: C-. then C-v opens the candidate in a vertical split (right),
;; C-x in a horizontal one (below).
;;
;; fzf-lua uses C-s for the horizontal split; `embark-general-map' binds C-s to
;; `embark-isearch-forward' and every action map inherits it.  Shadowing that in
;; just these maps would have been cheap — it isearches the CURRENT buffer for
;; the target's text, which is meaningless for a file path — but keeping
;; `embark-isearch-forward' uniformly reachable was preferred over parity on the
;; second key.  C-x it is.  (2/3 are not options: `embark-meta-map' binds every
;; digit to `digit-argument'.)
;;
;; Embark's own `o' (find-file-other-window / switch-to-buffer-other-window)
;; can't serve here: it defers to `split-window-sensibly', which picks the
;; direction from `split-width-threshold' rather than letting us choose.
;;
;; Two wrapper shapes are needed, because embark invokes the two kinds of action
;; differently:
;;
;;   - `find-file' / `switch-to-buffer' are interactive commands.  Embark
;;     injects the target into their minibuffer prompt, so the wrapper must
;;     `call-interactively' them — passing the target as an argument would
;;     bypass the injection machinery.
;;   - `embark-consult-goto-location' / `-goto-grep' are plain functions of one
;;     argument.  Embark calls them with the target directly, so the wrapper
;;     takes the same signature and must NOT be interactive.
;;
;; If the action errors or is aborted with C-g, the freshly created split is
;; left behind — inert, with focus still in the original window, since the
;; jumper's deferred re-selection (below) is never scheduled once `FN' has
;; signaled.  Deliberate: it's one C-w c away, and unwinding it would mean
;; wrapping every action in `condition-case' with window bookkeeping.

(defmacro my/embark-define-split-command (name split fn)
  "Define command NAME: split via SPLIT, select it, then `call-interactively' FN.
For embark actions that are interactive commands taking their target
through minibuffer injection."
  `(defun ,name ()
     ,(format "Split the window with `%s', then run `%s' there." split fn)
     (interactive)
     (select-window (,split))
     (call-interactively #',fn)))

(defmacro my/embark-define-split-jumper (name split fn)
  "Define function NAME: split via SPLIT, select it, then call FN with the target.
For embark actions that are plain one-argument functions."
  `(defun ,name (target)
     ,(format "Split the window with `%s', then `%s' TARGET there." split fn)
     (let ((win (,split)))
       (select-window win)
       (,fn target)
       ;; embark's non-command dispatch path (`embark--act') calls this
       ;; inside a plain `with-selected-window', not the command path's
       ;; variant that captures `final-window' and re-applies it after
       ;; unwinding.  Plain `with-selected-window' restores the window that
       ;; was selected *before* the call once its body returns, so the
       ;; `select-window' above is silently discarded the instant `,fn'
       ;; returns.  Deferring the re-selection past that unwind with a
       ;; zero-delay `run-at-time' — rather than embark's own private
       ;; `embark--run-after-command', which does the same thing but isn't
       ;; public API — lets focus land in the split after all.  `win' is
       ;; passed as a timer argument instead of closed over so this holds
       ;; regardless of lexical binding.
       (run-at-time 0 nil #'select-window win))))

(my/embark-define-split-command my/embark-find-file-right
                                split-window-right find-file)
(my/embark-define-split-command my/embark-find-file-below
                                split-window-below find-file)
(my/embark-define-split-command my/embark-switch-buffer-right
                                split-window-right switch-to-buffer)
(my/embark-define-split-command my/embark-switch-buffer-below
                                split-window-below switch-to-buffer)

(my/embark-define-split-jumper my/embark-goto-location-right
                               split-window-right embark-consult-goto-location)
(my/embark-define-split-jumper my/embark-goto-location-below
                               split-window-below embark-consult-goto-location)
(my/embark-define-split-jumper my/embark-goto-grep-right
                               split-window-right embark-consult-goto-grep)
(my/embark-define-split-jumper my/embark-goto-grep-below
                               split-window-below embark-consult-goto-grep)

;; Files and buffers already have maps; these shadow the inherited general-map.
(keymap-set embark-file-map   "C-v" #'my/embark-find-file-right)
(keymap-set embark-file-map   "C-x" #'my/embark-find-file-below)
(keymap-set embark-buffer-map "C-v" #'my/embark-switch-buffer-right)
(keymap-set embark-buffer-map "C-x" #'my/embark-switch-buffer-below)

;; consult's own categories have no `embark-keymap-alist' entry, so they fall
;; back to `embark-general-map'.  The split keys must NOT go there: general-map
;; is the parent of every action map, so C-v on a `symbol' or `kill-ring' target
;; would call a location-jumper on a non-location and error.  Give each category
;; its own map instead, inheriting general-map so all the ordinary actions stay.
;;
;; consult-line and consult-ripgrep are DIFFERENT categories with different
;; jumpers (`consult--get-location' vs `consult--grep-position'), hence two maps.
(defvar-keymap my/embark-consult-location-map
  :doc "Embark actions for `consult-location' targets (SPC g l results)."
  :parent embark-general-map
  "C-v" #'my/embark-goto-location-right
  "C-x" #'my/embark-goto-location-below)

(defvar-keymap my/embark-consult-grep-map
  :doc "Embark actions for `consult-grep' targets (SPC g p results)."
  :parent embark-general-map
  "C-v" #'my/embark-goto-grep-right
  "C-x" #'my/embark-goto-grep-below)

(setf (alist-get 'consult-location embark-keymap-alist)
      '(my/embark-consult-location-map))
(setf (alist-get 'consult-grep embark-keymap-alist)
      '(my/embark-consult-grep-map))

;;; embark.el ends here
