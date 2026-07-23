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
;; left behind — inert, with focus still in the original window.  Deliberate:
;; it's one C-w c away, and guarding it would mean wrapping every action in
;; `condition-case' with window bookkeeping.  (The two macros land back in the
;; original window for different reasons — see each macro below.)

;; On this macro's error path, focus stays in the original window because
;; embark's own command-dispatch path only re-applies the freshly selected
;; window via `final-window' on success (embark.el ~line 2178): the trailing
;; `(unless (eq final-window action-window) (select-window final-window))' at
;; ~2182-2183 is skipped as the signal from `FN' propagates.
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
  "Define function NAME: split via SPLIT, then show FN's jump target there.
For embark actions that are plain one-argument functions."
  `(defun ,name (target)
     ,(format "Split the window with `%s', then show `%s' TARGET there." split fn)
     (let ((win (,split)))
       (select-window win)
       (,fn target)
       ;; Capture where the jump actually landed, then force the split to show
       ;; it.  Two things conspire to make this necessary:
       ;;
       ;;   1. `consult--jump' (what `,fn' ultimately calls) reuses an EXISTING
       ;;      window if one already displays the target buffer, ignoring the
       ;;      split we just made — so after `,fn' the split may still show the
       ;;      old buffer while point sits in some other window.  Re-pointing
       ;;      `win' at the buffer/position the jump reached (captured here,
       ;;      synchronously) makes the split show the target either way.
       ;;   2. embark's non-command dispatch (`embark--act') runs this inside a
       ;;      plain `with-selected-window' — unlike the command path, it does
       ;;      NOT capture and re-apply a `final-window', so it restores the
       ;;      pre-call window the instant `,fn' returns and any `select-window'
       ;;      here is discarded.  Deferring past that unwind with a zero-delay
       ;;      `run-at-time' (not embark's private `embark--run-after-command')
       ;;      lets focus actually land in the split.
       ;;
       ;; The `window-live-p' guard keeps a window killed before the timer fires
       ;; from surfacing as an async `select-window' error in *Messages'.
       (let ((buf (current-buffer))
             (pos (point)))
         (run-at-time
          0 nil
          (lambda ()
            (when (window-live-p win)
              (set-window-buffer win buf)
              (set-window-point win pos)
              (select-window win))))))))

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
