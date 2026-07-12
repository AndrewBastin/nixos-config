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
;; VC segment glyphs, built from hex codepoints (NOT literal glyph chars):
;; literal Nerd-Font glyphs get silently stripped when this file is edited
;; through tooling, which is how an earlier version emitted two bare spaces
;; while the comment still claimed a branch icon.  Pure-ASCII source can't be
;; lost.  #xe725 = nf-dev-git_branch — used for both git and jj; jj is told
;; apart by its ref (the highlighted change-id), not by a distinct glyph.
(defconst my/ml--vc-glyphs
  (list (cons "Git" (string #xe725))
        (cons "JJ"  (string #xe725)))
  "Alist mapping a VC backend name (as it appears in `vc-mode') to its glyph.")

(defface my/ml-jj-change-unique
  '((t :foreground "#957FB8"))         ; Kanagawa oniViolet, ~ jj's magenta change-id
  "Mode-line face for the UNIQUE prefix of a jujutsu change-id.
Mirrors how `jj log' highlights the shortest unique prefix; the remaining
\(non-unique) characters are left unfaced so they take the normal mode-line
color.  Applied by `my/ml--jj-styled-changeid' (wired in via lisp/vc.el).")

(defun my/ml--jj-styled-changeid (prefix rest)
  "Build a two-tone jujutsu change-id string from PREFIX and REST.
PREFIX is the shortest unique change-id prefix (highlighted with
`my/ml-jj-change-unique'); REST is the remaining characters padding it out to
the display width (left unfaced).  Together they read like `jj log's own id."
  (concat (propertize prefix 'face 'my/ml-jj-change-unique) rest))

(defun my/ml--vc-format (vc-string)
  "Format VC-STRING for the mode line.
VC-STRING is a `vc-mode'-style string \" <Backend><state><ref>\": leading
space, the backend name, a one-char state indicator (-/:/@/!/?/^), then the
ref (git branch, or jj's shortest change-id).  Return \"<glyph> <ref>\" with
a backend-appropriate glyph (see `my/ml--vc-glyphs'; unknown backends fall
back to the branch glyph), or nil when VC-STRING is nil, not a string, or
has no parseable backend + ref."
  (when (and vc-string (stringp vc-string)
             (string-match
              "\\`[[:space:]]*\\([A-Za-z]+\\)[-:@!?^ ]?\\(.*\\)\\'" vc-string))
    (let* ((backend (match-string 1 vc-string))
           (ref     (string-trim (match-string 2 vc-string)))
           (glyph   (or (cdr (assoc backend my/ml--vc-glyphs))
                        (cdr (assoc "Git" my/ml--vc-glyphs)))))  ; fallback: the branch glyph
      (unless (string= ref "")
        (concat glyph " " ref)))))

(defun my/ml-vc-branch ()
  "VC segment for the mode line: a backend-appropriate glyph plus the current ref.
Reads the buffer-local `vc-mode' (set by Emacs' VC on file visit) and delegates
to `my/ml--vc-format'.  Empty (nil) in non-VC buffers so they stay clean.  git
buffers read the branch glyph + branch name; jujutsu buffers (via the vc-jj
backend, see lisp/vc.el) read the branch glyph + the 8-char change-id, whose
unique prefix is highlighted (see `my/ml--jj-styled-changeid')."
  (my/ml--vc-format vc-mode))

(defun my/ml-file-name ()
  "Filename segment, lualine-style: the file path *relative to the active dir*
when the file is a child of it (see `my/active-dir' in ghostel.el), otherwise
the stock buffer identification.  Guarded with `fboundp' so the mode line still
renders if this is evaluated before ghostel.el has loaded."
  (let ((file (buffer-file-name))
        (dir  (and (fboundp 'my/active-dir)
                   (file-name-as-directory (expand-file-name (my/active-dir))))))
    (if (and file dir (string-prefix-p dir (expand-file-name file)))
        (propertize (file-relative-name (expand-file-name file) dir)
                    'face 'mode-line-buffer-id)
      mode-line-buffer-identification)))

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
   (:eval (my/ml-file-name))           ; path relative to the active/pinned dir
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
