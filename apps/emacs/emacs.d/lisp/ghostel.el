;;; ghostel.el --- Ghostel terminal: evil integration, openers, file shim, startup banner  -*- lexical-binding: t; -*-

;; ==========================================================================
;; 1. Core setup: evil integration, escape behaviour
;; ==========================================================================

;; The native module ships bundled next to ghostel.el (see apps/emacs/ghostel.nix),
;; which is the loader's default location, so `ghostel-module-directory' is left
;; nil and ghostel finds the module on its own.

;; Evil integration for ghostel terminals: enable evil-ghostel-mode in every
;; ghostel buffer (autoloaded, so this pulls evil-ghostel in on first use).
(add-hook 'ghostel-mode-hook #'evil-ghostel-mode)

;; Send insert-state ESC straight to the terminal (readline/zle meta keys,
;; TUIs, ESC-ESC) instead of leaving insert state; use C-<escape> to drop to
;; evil normal state instead (mirrors evil's usual insert-state ESC binding).
(setq evil-ghostel-escape 'terminal)

;; Drop the "ghostel" prefix from buffer names (what shows in the modeline).
;; Stock ghostel names buffers "*ghostel: TITLE*" (by title) and "*ghostel*"
;; (no title yet); we want just the terminal's own TITLE, e.g. "*~/nixos-config*".
;; `ghostel-buffer-name' is the title-less base; the name function renames to
;; the TITLE on each OSC-2 title report (nil keeps the base, as upstream does).
(setq ghostel-buffer-name "*terminal*")

(defun my/ghostel-buffer-name (title)
  "Name a ghostel buffer \"*TITLE*\", with no \"ghostel\" prefix.
Like `ghostel-buffer-name-by-title' but without the prefix; returns nil for an
empty TITLE so the base `ghostel-buffer-name' is kept."
  (and title (not (string= "" title))
       (format "*%s*" title)))

(setq ghostel-buffer-name-function #'my/ghostel-buffer-name)

;; ==========================================================================
;; 2. Clipboard paste + evil-ghostel key bindings
;; ==========================================================================

;; Paste the *system clipboard* (not the kill ring) into the terminal, bound to
;; C-S-v below.  We read CLIPBOARD directly so it works regardless of the
;; kill-ring state, and send it via `ghostel-paste-string' which wraps it in
;; bracketed paste so the shell sees it as pasted rather than typed.
(defun my/ghostel-paste-clipboard ()
  "Paste the system clipboard into the ghostel terminal (bracketed paste)."
  (interactive)
  (let ((text (gui-get-selection 'CLIPBOARD)))
    (if (and text (not (string-empty-p text)))
        (ghostel-paste-string text)
      (user-error "System clipboard is empty"))))

(with-eval-after-load 'evil-ghostel
  (evil-define-key* 'insert evil-ghostel-mode-map
                    ;; C-<escape> is the one Emacs key in insert state: drop to
                    ;; normal mode.  Everything else should reach the program.
                    (kbd "C-<escape>") #'evil-normal-state
                    ;; In insert state, send C-c / C-x straight to the terminal
                    ;; so programs (Claude Code, nano, readline, …) get them.
                    ;; evil-ghostel's passthrough list omits c/x, and ghostel
                    ;; reserves C-c as an Emacs prefix (C-c C-c) — so without
                    ;; this a lone C-c is swallowed by Emacs instead of
                    ;; interrupting.  This evil aux binding outranks that prefix.
                    (kbd "C-c") #'ghostel-send-C-c
                    (kbd "C-x") (lambda () (interactive) (ghostel-send-key "x" "ctrl"))
                    ;; C-t opens a brand-new terminal buffer; C-<tab> /
                    ;; C-S-<tab> cycle forward / backward through the ghostel
                    ;; buffers in order (name-sorted, wraps).  Like C-c above,
                    ;; these evil aux bindings outrank the terminal passthrough,
                    ;; so they stay Emacs commands.
                    (kbd "C-t") #'my/ghostel-fresh
                    (kbd "C-<tab>") #'ghostel-next
                    (kbd "C-S-<tab>") #'ghostel-previous
                    (kbd "C-<iso-lefttab>") #'ghostel-previous
                    ;; C-S-v pastes the system clipboard into the terminal.
                    (kbd "C-S-v") #'my/ghostel-paste-clipboard))

;; ==========================================================================
;; 3. Terminal opener defuns (fresh / split / vsplit)
;; ==========================================================================

;; --- Ghostel terminal openers (bound under SPC t below) ------------------
;; `ghostel' with a *non-numeric* prefix arg forces a brand-new terminal
;; (see its docstring); the list '(4) is exactly what C-u hands a command, so
;; passing it makes each call spawn a fresh buffer instead of reusing the
;; default-named one.  The split helpers create the new window first, select
;; into it, then let `ghostel' open there (it uses a same-window display
;; action, so it lands in whatever window is selected).
(defun my/ghostel-fresh ()
  "Open a brand-new Ghostel terminal in the current window."
  (interactive)
  (ghostel '(4)))

(defun my/ghostel-split ()
  "Open a fresh Ghostel terminal in a new split below (vim :split)."
  (interactive)
  (select-window (split-window-below))
  (ghostel '(4)))

(defun my/ghostel-vsplit ()
  "Open a fresh Ghostel terminal in a new split to the right (vim :vsplit)."
  (interactive)
  (select-window (split-window-right))
  (ghostel '(4)))

;; ==========================================================================
;; 4. Opening files from inside a ghostel terminal (OSC-52 receiver half)
;; ==========================================================================

;; --- Opening files *from inside* a ghostel terminal ----------------------
;; Goal: shell commands `e FILE' / `es FILE' / `ev FILE' that open FILE in
;; Emacs (current window / split below / split right).  Two halves:
;;
;; HALF 1 — the Emacs receiver.  ghostel lets the shell call a WHITELISTED
;; Emacs function: the shell emits an OSC-52 ";e" escape (via the `ghostel_cmd'
;; helper its shell integration defines) carrying a function name + string
;; args, and `ghostel--osc52-eval' looks the name up in `ghostel-eval-cmds'
;; and applies it.  `find-file' already ships in that whitelist (that's `e');
;; we add split/vsplit variants for `es'/`ev'.  Args arrive as strings.
(defun my/ghostel-find-file-split (filename)
  "Open FILENAME in a split below the terminal (vim :split)."
  (select-window (split-window-below))
  (find-file filename))

(defun my/ghostel-find-file-vsplit (filename)
  "Open FILENAME in a split right of the terminal (vim :vsplit)."
  (select-window (split-window-right))
  (find-file filename))

(with-eval-after-load 'ghostel
  (add-to-list 'ghostel-eval-cmds '("find-file-split"  my/ghostel-find-file-split))
  (add-to-list 'ghostel-eval-cmds '("find-file-vsplit" my/ghostel-find-file-vsplit)))

;; ==========================================================================
;; 5. Shell shim: inject e / es / ev without editing ~/.zshrc
;; ==========================================================================

;; HALF 2 — defining the `e'/`es'/`ev' shell functions WITHOUT editing any
;; shell rc (my ~/.zshrc is read-only, home-manager-managed).  Trick: ghostel
;; loads its zsh integration by setting the env var EMACS_GHOSTEL_PATH and
;; having the spawned shell source "$EMACS_GHOSTEL_PATH/etc/shell/ghostel.zsh"
;; — and nothing else in the shell reads that var.  So we point it at a tiny
;; *shim* we generate, which sources ghostel's real integration (to get
;; `ghostel_cmd') and then defines our three functions.
;;
;; `ghostel-pre-spawn-hook' is the supported seam: it runs with
;; `process-environment' dynamically bound to the about-to-spawn child env, so
;; a plain `setenv' here only rewrites EMACS_GHOSTEL_PATH for that one shell.
(defvar my/ghostel-shim-dir
  (expand-file-name "ghostel-shim" user-emacs-directory)
  "Directory holding our generated ghostel zsh-integration shim.")

(defun my/ghostel-install-shell-shim ()
  "Redirect EMACS_GHOSTEL_PATH to a shim that adds `e'/`es'/`ev'.
Run from `ghostel-pre-spawn-hook'.  Only acts for zsh — for other shells we
leave ghostel's stock integration untouched (the shim only ships a .zsh)."
  (let ((real (getenv "EMACS_GHOSTEL_PATH")))   ; ghostel set this just now
    (when (and real (string-match-p "zsh" (or ghostel-shell "")))
      (let* ((dir (expand-file-name "etc/shell" my/ghostel-shim-dir))
             (shim (expand-file-name "ghostel.zsh" dir))
             ;; the genuine integration file we must load first, for `ghostel_cmd'
             (real-integ (expand-file-name "etc/shell/ghostel.zsh" real)))
        (make-directory dir t)
        (with-temp-file shim
          (insert
           "# Auto-generated by init.el — regenerated on each ghostel spawn.\n"
           "# Load ghostel's real zsh integration (defines `ghostel_cmd'),\n"
           "# then add file-opening helpers that call whitelisted Emacs cmds.\n"
           "'builtin' 'source' '--' " (shell-quote-argument real-integ) "\n"
           ;; restore the var so nothing downstream sees our shim path
           "export EMACS_GHOSTEL_PATH=" (shell-quote-argument real) "\n"
           ;; ${1:a} = absolutise FILE against the shell's cwd, so it resolves
           ;; no matter what Emacs's `default-directory' happens to be.
           "e()  { ghostel_cmd find-file        \"${1:a}\"; }\n"
           "es() { ghostel_cmd find-file-split  \"${1:a}\"; }\n"
           "ev() { ghostel_cmd find-file-vsplit \"${1:a}\"; }\n"))
        (setenv "EMACS_GHOSTEL_PATH" my/ghostel-shim-dir)))))

(add-hook 'ghostel-pre-spawn-hook #'my/ghostel-install-shell-shim)

;; ==========================================================================
;; 6. Startup banner
;; ==========================================================================

;; Open a ghostel terminal on startup instead of the splash/scratch buffer, and
;; greet it with a dashboard-style banner (only this first/startup terminal).
;; Runs from `emacs-startup-hook' (after the initial frame/window exist) so the
;; terminal is sized to the real window from the start.
(setq inhibit-startup-screen t)

(defun my/ghostel-startup ()
  "Open the startup ghostel terminal and print the banner inside it.
We send a shell command (not raw output) so the normal spawn path — and
thus shell integration / evil-ghostel — stays intact.  The leading space
keeps it out of shell history (with `hist_ignore_space'), and `clear'
wipes the echoed command so only the banner remains above the prompt."
  (let ((buf (ghostel))
        (banner (expand-file-name "banner.txt" my/config-dir)))
    (when (file-readable-p banner)
      (with-current-buffer buf
        ;; Wrap the banner in a 24-bit (truecolor) ANSI escape so it renders in
        ;; #c34043 = rgb(195,64,67).  `\033' is written as the literal text
        ;; \033 (note the doubled backslash in elisp) so the shell's `printf'
        ;; emits the ESC byte at runtime — typing a raw ESC into the line editor
        ;; would be misread by zsh's ZLE as the start of a key sequence.
        (ghostel-send-string
         (format
          " clear; printf '\\033[38;2;195;64;67m'; cat %s; printf '\\033[0m'\n"
          (shell-quote-argument banner)))))))

(add-hook 'emacs-startup-hook #'my/ghostel-startup)

;;; ghostel.el ends here
