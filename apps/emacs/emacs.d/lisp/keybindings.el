;;; keybindings.el --- which-key, leader map, eglot/neotree keys  -*- lexical-binding: t; -*-

(which-key-mode)

;; --- Leader key (SPC), mirroring the nvim layout -------------------------
(evil-define-key '(normal visual) 'global
  (kbd "<leader>e")        #'neotree-toggle          ; toggle file viewer
  (kbd "<leader>f")        #'consult-fd              ; fuzzy find files
  (kbd "<leader><leader>") #'project-find-file       ; project (git) files
  (kbd "<leader>bb")       #'my/consult-buffer-no-special ; switch buffer (hide *special*)
  (kbd "<leader>bB")       #'consult-buffer          ; switch buffer (all, incl. *special*)
  (kbd "<leader>gp")       #'consult-ripgrep         ; project grep
  (kbd "<leader>gl")       #'consult-line            ; search lines in buffer
  (kbd "<leader>d")        #'consult-flymake         ; document diagnostics
  (kbd "<leader>s")        #'consult-imenu           ; document symbols
  (kbd "<leader>S")        #'consult-eglot-symbols   ; workspace symbols
  (kbd "<leader>ca")       #'eglot-code-actions      ; LSP code actions
  (kbd "<leader>cr")       #'eglot-rename            ; LSP rename
  (kbd "<leader>cf")       #'my/change-major-mode    ; change filetype
  (kbd "<leader>tt")       #'my/ghostel-fresh        ; new ghostel terminal
  (kbd "<leader>tb")       #'ghostel-list-buffers    ; pick a ghostel buffer
  (kbd "<leader>ts")       #'my/ghostel-split        ; ghostel in a split
  (kbd "<leader>tv")       #'my/ghostel-vsplit       ; ghostel in a vsplit
  (kbd "<leader>GG")       #'magit-status            ; git status
  (kbd "<leader>Gc")       #'magit-log-buffer-file   ; commits of this file
  (kbd "<leader>Gdo")      #'magit-diff-working-tree ; open diff view
  (kbd "<leader>Gdc")      #'magit-mode-bury-buffer  ; close diff view
  (kbd "<leader>xd")       #'flymake-show-buffer-diagnostics
  (kbd "<leader>xn")       #'flymake-goto-next-error
  (kbd "<leader>xp")       #'flymake-goto-prev-error
  ;; Extra (not in nvim): Emacs's own help system, handy while learning.
  (kbd "<leader>hf")       #'describe-function
  (kbd "<leader>hv")       #'describe-variable
  (kbd "<leader>hk")       #'describe-key)

;; LSP "go to" keys, active only where eglot is attached (like nvim's lspBuf).
;; Binding into `eglot-mode-map' means these only shadow evil's defaults (gd, K)
;; inside code buffers with a live language server.
(with-eval-after-load 'eglot
  (evil-define-key 'normal eglot-mode-map
    (kbd "K")  #'eldoc-box-help-at-point   ; hover documentation (childframe popup)
    (kbd "gd") #'xref-find-definitions
    (kbd "gD") #'xref-find-references
    (kbd "gi") #'eglot-find-implementation
    (kbd "gt") #'eglot-find-typeDefinition))

;; neotree opens its buffer in evil normal state, whose keymap shadows
;; neotree-mode-map — so plain RET hits `evil-ret', not neotree.  Re-bind
;; neotree's commands for normal state (same trick as the eglot keys above) so
;; they take precedence.  Evil motions j/k still move through the tree.
(with-eval-after-load 'neotree
  (evil-define-key 'normal neotree-mode-map
    (kbd "RET") #'neotree-enter                  ; open file / toggle directory
    (kbd "TAB") #'neotree-quick-look             ; peek without leaving the tree
    (kbd "o")   #'neotree-enter
    (kbd "s")   #'neotree-enter-vertical-split   ; open in a vertical split
    (kbd "S")   #'neotree-enter-horizontal-split ; …horizontal split
    (kbd "g")   #'neotree-refresh
    (kbd "H")   #'neotree-hidden-file-toggle     ; show/hide dotfiles
    (kbd "R")   #'neotree-change-root            ; make dir-at-point the root
    (kbd "c")   #'neotree-create-node            ; create file/dir
    (kbd "d")   #'neotree-delete-node
    (kbd "r")   #'neotree-rename-node
    (kbd "q")   #'neotree-hide))

;; Name the which-key groups so the SPC menu reads nicely.
(with-eval-after-load 'which-key
  (which-key-add-key-based-replacements
    "SPC b"   "buffer"
    "SPC g"   "search"
    "SPC c"   "code"
    "SPC G"   "git"
    "SPC G d" "diff"
    "SPC x"   "diagnostics"
    "SPC h"   "help"
    "SPC t"   "terminal"))

;;; keybindings.el ends here
