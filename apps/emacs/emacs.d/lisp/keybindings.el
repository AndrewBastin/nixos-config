;;; keybindings.el --- which-key, leader map, eglot/neotree keys  -*- lexical-binding: t; -*-

;; Show the key hints after 0.3s instead of the default 1.0s — fast enough to
;; act as a cheat-sheet mid-chord, slow enough not to flash on fluent input.
(setq which-key-idle-delay 0.3)
(which-key-mode)

;; --- Leader key (SPC), mirroring the nvim layout -------------------------
(evil-define-key '(normal visual) 'global
  (kbd "<leader>e")        #'my/neotree-toggle       ; toggle file viewer (rooted at active dir)
  (kbd "<leader>f")        #'consult-fd              ; fuzzy find files
  (kbd "<leader><leader>") #'project-find-file       ; project (git) files
  (kbd "<leader>bb")       #'my/consult-buffer-no-special ; switch buffer (hide *special*)
  (kbd "<leader>bB")       #'consult-buffer          ; switch buffer (all, incl. *special*)
  (kbd "<leader>gp")       #'consult-ripgrep         ; project grep
  (kbd "<leader>gl")       #'consult-line            ; search lines in buffer
  (kbd "<leader>d")        #'consult-flymake         ; document diagnostics
  (kbd "<leader>k")        #'my/eldoc-doc-split      ; LSP docs in a focusable split
  (kbd "<leader>s")        #'consult-imenu           ; document symbols
  (kbd "<leader>S")        #'consult-eglot-symbols   ; workspace symbols
  (kbd "<leader>ca")       #'eglot-code-actions      ; LSP code actions
  (kbd "<leader>cr")       #'eglot-rename            ; LSP rename
  (kbd "<leader>cf")       #'my/change-major-mode    ; change filetype
  (kbd "<leader>tt")       #'my/ghostel-fresh        ; new ghostel terminal
  (kbd "<leader>tb")       #'ghostel-list-buffers    ; pick a ghostel buffer
  (kbd "<leader>ts")       #'my/ghostel-split        ; ghostel in a split
  (kbd "<leader>tv")       #'my/ghostel-vsplit       ; ghostel in a vsplit
  (kbd "<leader>GG")       #'my/vc-status-dwim       ; status: jjui in jj repos, else magit
  (kbd "<leader>Gc")       #'magit-log-buffer-file   ; commits of this file
  (kbd "<leader>Gd")       #'diffview-open           ; diffview: side-by-side + panel (q closes)
  (kbd "<leader>xd")       #'flymake-show-buffer-diagnostics
  (kbd "<leader>xn")       #'flymake-goto-next-error
  (kbd "<leader>xp")       #'flymake-goto-prev-error
  ;; Extra (not in nvim): Emacs's own help system, handy while learning.
  (kbd "<leader>hf")       #'describe-function
  (kbd "<leader>hv")       #'describe-variable
  (kbd "<leader>hk")       #'describe-key)

;; mini.bracketed parity (nvim): ]d / [d jump to the next/previous diagnostic.
(evil-define-key 'normal 'global
  (kbd "]d") #'flymake-goto-next-error
  (kbd "[d") #'flymake-goto-prev-error)

;; mini.comment parity: <leader>cc comments the line / the visual selection,
;; coexisting with the <leader>ca/cr/cf code keys just like in nvim.  Only
;; nvim's <leader>c comment *operator* can't be ported — Emacs keymaps have no
;; vim-style timeout disambiguation, so a command on the bare <leader>c would
;; swallow the prefix.  gc{motion} (evil-commentary) covers that role.
(evil-define-key 'normal 'global (kbd "<leader>cc") #'evil-commentary-line)
(evil-define-key 'visual 'global (kbd "<leader>cc") #'evil-commentary)

;; --- Global text size: C-+ increase / C-- decrease / C-= reset ----------
;; `global-text-scale-adjust' resizes the *default face* height, so the change
;; applies across every buffer and frame — unlike `text-scale-adjust', which is
;; buffer-local.  It picks increase/decrease/reset from the final key pressed
;; (`+'/`='/`-'/`0'), so `=' would actually increase; reset needs `0' spoofed in.
;; After the first press a transient map lets you keep tapping +/-/0 to continue.
(defun my/global-text-scale-reset ()
  "Reset the global text size to its original height."
  (interactive)
  (let ((last-command-event ?0))
    (global-text-scale-adjust 1)))

(global-set-key (kbd "C-+") #'global-text-scale-adjust)   ; increase
(global-set-key (kbd "C--") #'global-text-scale-adjust)   ; decrease
(global-set-key (kbd "C-=") #'my/global-text-scale-reset) ; reset to original

;; LSP "go to" keys, active only where eglot is attached (like nvim's lspBuf).
;; Binding into `eglot-mode-map' means these only shadow evil's defaults (gd, K)
;; inside code buffers with a live language server.
(with-eval-after-load 'eglot
  (evil-define-key 'normal eglot-mode-map
    (kbd "K")  #'my/eldoc-doc-toggle       ; hover documentation popup (K again closes)
    (kbd "gd") #'xref-find-definitions
    (kbd "gr") #'xref-find-references
    (kbd "gi") #'eglot-find-implementation
    (kbd "gt") #'eglot-find-typeDefinition)
  ;; Push a jumplist entry before these LSP "go to" commands so C-o
  ;; (`evil-jump-backward') returns here afterwards — like Vim's jumplist.
  ;; evil already flags gd/gr (xref-find-definitions / -references); the eglot
  ;; finders below need it too, otherwise a *same-file* jump isn't recorded
  ;; (cross-file ones are caught by evil's buffer-crossing hook regardless).
  (evil-set-command-property 'eglot-find-implementation :jump t)
  (evil-set-command-property 'eglot-find-typeDefinition :jump t))

;; neotree opens its buffer in evil normal state, whose keymap shadows
;; neotree-mode-map — so plain RET hits `evil-ret', not neotree.  Re-bind
;; neotree's commands for normal state (same trick as the eglot keys above) so
;; they take precedence.  Evil motions j/k still move through the tree.
;;
;; These mirror neo-tree.nvim's default keymap (the nvim file viewer) as closely
;; as neotree's command set allows, so muscle memory carries across, and
;; BACKSPACE walks up to the parent dir.  nvim's `w` (open in window-picker) is
;; omitted: it needs ace-window, which isn't installed.  We deliberately do NOT
;; bind SPC to toggle_node (which nvim does): leaving it unbound lets the global
;; leader stay live inside the tree, so SPC e closes neotree and SPC f/gp/etc.
;; still work here.  RET already toggles a directory.
(with-eval-after-load 'neotree
  ;; Drop the redundant yes/no confirmations neotree asks *after* you've already
  ;; committed to an action.  `off-p' is neotree's own always-return-t stub.
  ;; Creating a file/dir already made you type the name at the "Filename:"
  ;; prompt, and change-root is non-destructive — the extra "Do you want to…?"
  ;; adds nothing.  The DELETE confirmations are deliberately left at their
  ;; `yes-or-no-p' default: `d' is a single keypress that could be hit by
  ;; accident, so deleting a file, a recursive dir delete, and killing that
  ;; dir's open buffers all still ask first.
  (setq neo-confirm-create-file      'off-p
        neo-confirm-create-directory 'off-p
        neo-confirm-change-root      'off-p)
  (evil-define-key 'normal neotree-mode-map
    (kbd "RET")       #'neotree-enter                  ; open file / toggle directory
    (kbd "<backspace>") #'neotree-select-up-node       ; navigate_up (to parent)
    (kbd ".")         #'neotree-change-root            ; set_root (dir-at-point becomes root)
    (kbd "P")         #'neotree-quick-look             ; toggle_preview (peek without leaving)
    (kbd "s")         #'neotree-enter-vertical-split   ; open_vsplit
    (kbd "S")         #'neotree-enter-horizontal-split ; open_split
    (kbd "z")         #'neotree-collapse-all           ; close_all_nodes
    (kbd "R")         #'neotree-refresh                ; refresh
    (kbd "a")         #'neotree-create-node            ; add (file/dir)
    (kbd "d")         #'neotree-delete-node            ; delete
    (kbd "r")         #'neotree-rename-node            ; rename
    (kbd "c")         #'neotree-copy-node              ; copy
    (kbd "H")         #'neotree-hidden-file-toggle     ; toggle_hidden (dotfiles)
    (kbd "q")         #'neotree-hide))                 ; close_window

;; Name the which-key groups so the SPC menu reads nicely.
(with-eval-after-load 'which-key
  (which-key-add-key-based-replacements
    "SPC b"   "buffer"
    "SPC g"   "search"
    "SPC c"   "code"
    "SPC G"   "git"
    "SPC G d" "diffview"
    "SPC x"   "diagnostics"
    "SPC h"   "help"
    "SPC t"   "terminal"))

;;; keybindings.el ends here
