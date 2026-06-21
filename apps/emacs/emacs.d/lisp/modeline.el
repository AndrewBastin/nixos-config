;;; modeline.el --- Lualine-style mode line with evil state tag  -*- lexical-binding: t; -*-

;; --- Mode line -------------------------------------------------------------
;; `mode-line-format' is just a list of constructs Emacs renders left-to-right.
;; The stock value carries a lot we don't want right now (coding-system / EOL
;; info, the full minor-mode lighter list, the buffer-percentage), so we list
;; only the segments we care about.
;;
;; Evil normally splices its state tag into the mode line *for us*, positioned
;; relative to `mode-line-position' (see `evil-mode-line-format', default
;; `before') — which lands it mid-line, not at the far left.  We want it
;; leftmost and fully under our control, so we turn evil's auto-placement off
;; (`evil-mode-line-format' nil) and render the tag ourselves.
;;
;; Note we do NOT reuse evil's `evil-mode-line-tag' *symbol* here: every state
;; change runs `evil-refresh-mode-line', which does
;;   (setq mode-line-format (delq 'evil-mode-line-tag mode-line-format))
;; i.e. it strips that symbol out of the list — and with placement disabled it
;; never puts it back.  So instead we use an `:eval' construct that recomputes
;; the tag from the buffer-local `evil-state' on each redisplay.  evil's `delq'
;; only matches the bare symbol, so it can't disturb our `:eval' form.
(setq evil-mode-line-format nil)

;; A colored NORMAL/INSERT/VISUAL… block, styled after the Kanagawa lualine
;; "mode" segment.  Each `defface' is the dark-text-on-accent colour pair that
;; lualine uses for that mode (see kanagawa.nvim lua/lualine/themes/kanagawa.lua
;; mapped through its wave palette):
;;   normal  → fun/crystalBlue   insert → diag.ok/springGreen
;;   visual  → keyword/oniViolet replace → constant/surimiOrange
;;   operator→ operator/boatYellow2.  Defining real faces (rather than baking the
;; colours into the string) means you can later `M-x customize-face' them or have
;; another theme override them.  `:weight bold' gives the bit of boldness asked.
(defface my/ml-evil-normal   '((t :foreground "#16161D" :background "#7E9CD8" :weight bold))
  "Mode-line tag face for evil normal state.")
(defface my/ml-evil-insert   '((t :foreground "#1F1F28" :background "#98BB6C" :weight bold))
  "Mode-line tag face for evil insert state.")
(defface my/ml-evil-visual   '((t :foreground "#1F1F28" :background "#957FB8" :weight bold))
  "Mode-line tag face for evil visual state.")
(defface my/ml-evil-replace  '((t :foreground "#1F1F28" :background "#FFA066" :weight bold))
  "Mode-line tag face for evil replace state.")
(defface my/ml-evil-operator '((t :foreground "#1F1F28" :background "#C0A36E" :weight bold))
  "Mode-line tag face for evil operator-pending state.")
(defface my/ml-evil-emacs    '((t :foreground "#1F1F28" :background "#E46876" :weight bold))
  "Mode-line tag face for evil emacs state (warns: vim keys are off).")

;; Map each evil state symbol to (LABEL . FACE).  Visual sub-states (line/block)
;; all report `evil-state' = `visual', so one entry covers them.
(defvar my/evil-state-tags
  '((normal   "NORMAL"  my/ml-evil-normal)
    (insert   "INSERT"  my/ml-evil-insert)
    (visual   "VISUAL"  my/ml-evil-visual)
    (replace  "REPLACE" my/ml-evil-replace)
    (operator "O-PEND"  my/ml-evil-operator)
    (motion   "MOTION"  my/ml-evil-normal)
    (emacs    "EMACS"   my/ml-evil-emacs))
  "Alist mapping an evil state to its mode-line LABEL and FACE.")

(defun my/evil-mode-line-tag ()
  "Return the propertized evil-state block for the mode line.
Empty string in buffers with no evil state (so non-evil buffers stay clean)."
  (when (bound-and-true-p evil-state)
    (let* ((entry (cdr (assq evil-state my/evil-state-tags)))
           (label (or (car entry) (upcase (symbol-name evil-state))))
           (face  (or (cadr entry) 'my/ml-evil-normal)))
      (propertize (format " %s " label) 'face face))))

;; --- lualine-style segment helpers ----------------------------------------
;; Small `:eval' helpers that mirror individual lualine components from my
;; Neovim config, so the Emacs mode line reads the same way.
(defun my/ml-vc-branch ()
  "Git branch with a Nerd-Font branch icon, like lualine's `branch'.
`vc-mode' is a string like \" Git-main\": the backend name, a one-char state
indicator (-/:/@…), then the branch.  We strip that prefix and prepend the
 glyph (U+E725 — the same icon the nvim config uses)."
  (when (and vc-mode (stringp vc-mode))
    (let ((branch (replace-regexp-in-string "\\`[[:space:]]*[A-Za-z]+[-:@!?^]" ""
                                             vc-mode)))
      (concat "  " (string-trim branch)))))   ; leading glyph is U+E725 (nf-dev-git_branch)

(defun my/ml-coding-system ()
  "Buffer encoding name (e.g. \"utf-8\"), like lualine's `encoding'.
`coding-system-base' drops the line-ending variant: utf-8-unix → utf-8."
  (symbol-name (coding-system-base (or buffer-file-coding-system 'undecided))))

(defun my/ml-file-format ()
  "Line-ending style \"unix\"/\"dos\"/\"mac\", like lualine's `fileformat'.
`coding-system-eol-type' returns 0/1/2, or a vector when undetermined."
  (pcase (coding-system-eol-type (or buffer-file-coding-system 'undecided))
    (0 "unix") (1 "dos") (2 "mac") (_ "")))

;; Layout mirrors lualine's sections: a b c | x y z (| = right-align boundary).
(setq-default
 mode-line-format
 '("%e"                                ; reserved: shows a warning if out of memory
   ;; ── lualine_a: mode ──
   (:eval (my/evil-mode-line-tag))     ; NORMAL/INSERT/VISUAL… colored — leftmost
   " "
   ;; ── lualine_b: branch · diagnostics ──  (diff counts would need diff-hl)
   (:eval (my/ml-vc-branch))
   (flymake-mode flymake-mode-line-format)
   "  "
   ;; ── lualine_c: filename ──  (stock buffer identification, not the path)
   mode-line-modified                  ; **/--/%% modified · read-only marker
   " "
   mode-line-buffer-identification
   mode-line-format-right-align        ; everything past here hugs the right edge
   ;; ── lualine_x: encoding · fileformat · filetype ──
   (:eval (my/ml-coding-system))
   "  "
   (:eval (my/ml-file-format))
   "  "
   mode-name                           ; filetype ≈ major mode
   "  "
   ;; ── lualine_y: progress ──
   "%p"                                ; Top / Bot / All / NN%
   "  "
   ;; ── lualine_z: location ──
   "%l:%c"                             ; line:column
   "  "))                              ; trailing pad so it doesn't hug the edge

;;; modeline.el ends here
