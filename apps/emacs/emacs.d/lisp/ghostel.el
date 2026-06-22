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

;; Rename buffers "term: TITLE" instead of stock ghostel's "*ghostel: TITLE*"
;; (this is what shows in the modeline).  The "term: " prefix doubles as a
;; marker: it makes terminals distinguishable from file paths (used by the
;; jumplist integration in section 4), while reading cleanly in the buffer list.
;; `ghostel-buffer-name' is the title-less base, only seen for the instant
;; before the first cwd report arrives.
(setq ghostel-buffer-name "term:")

(defun my/ghostel-foreground-program ()
  "Return the foreground program running in this ghostel terminal, or nil.
At the shell prompt (nothing running) returns nil.  Linux-only: it reads the
controlling terminal's foreground process group (the `tpgid' field of the
shell's /proc/PID/stat) and then that group leader's `comm'.  Returns nil on
other systems or if anything can't be read."
  (when-let* (((eq system-type 'gnu/linux))
              (pid (bound-and-true-p ghostel--pid))
              (stat (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents (format "/proc/%d/stat" pid))
                        (buffer-string))))
              ;; "PID (comm) state ppid pgrp session tty tpgid …".  comm can
              ;; contain spaces and parens, so split on the LAST ")"; the
              ;; greedy ".*" before it backtracks to that final paren.
              ((string-match ".*) \\(.*\\)" stat)))
    (let* ((fields (split-string (match-string 1 stat)))
           (pgrp  (string-to-number (nth 2 fields)))   ; shell's own group
           (tpgid (string-to-number (nth 5 fields))))  ; terminal's fg group
      ;; tpgid == pgrp means the shell itself is in the foreground (prompt).
      (when (and (> tpgid 0) (/= tpgid pgrp))
        (ignore-errors
          (string-trim
           (with-temp-buffer
             (insert-file-contents (format "/proc/%d/comm" tpgid))
             (buffer-string))))))))

(defun my/ghostel-buffer-name (title)
  "Name a ghostel buffer \"term: …\", with no \"ghostel\" prefix or asterisks.
With a terminal TITLE set, use \"term: TITLE\".  Otherwise fall back to the
current directory plus the foreground program when one is running, e.g.
\"term: ~/nixos-config: nvim\" — or just \"term: ~/nixos-config\" at the prompt."
  (if (and title (not (string= "" title)))
      (format "term: %s" title)
    (let ((dir  (abbreviate-file-name (directory-file-name default-directory)))
          (prog (my/ghostel-foreground-program)))
      (if prog
          (format "term: %s: %s" dir prog)
        (format "term: %s" dir)))))

(setq ghostel-buffer-name-function #'my/ghostel-buffer-name)

;; The name function runs on title/cwd reports, but NOT when a command merely
;; starts or stops — so without this the program part would only refresh on the
;; next `cd'.  Re-apply the name on the command start/finish markers (OSC 133),
;; deferred slightly so the new foreground process has exec'd before we look.
(defun my/ghostel-refresh-name (buffer &rest _)
  "Recompute and re-apply BUFFER's managed ghostel name (deferred)."
  (when (buffer-live-p buffer)
    (run-at-time
     0.1 nil
     (lambda ()
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (when ghostel-buffer-name-function
             (let ((title (and ghostel--term (ghostel--get-title ghostel--term))))
               (ghostel--rename-managed
                (funcall ghostel-buffer-name-function title))))))))))

(with-eval-after-load 'ghostel
  (add-hook 'ghostel-command-start-functions  #'my/ghostel-refresh-name)
  (add-hook 'ghostel-command-finish-functions #'my/ghostel-refresh-name))

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
                    (kbd "C-S-v") #'my/ghostel-paste-clipboard)
  ;; The new-terminal / cycle shortcuts should also work after dropping to
  ;; normal state (for scrollback, copying, …), where the insert-state map
  ;; above no longer applies.  The C-c/C-x/C-S-v passthroughs stay insert-only
  ;; since they only make sense while sending keys to the program.
  (evil-define-key* 'normal evil-ghostel-mode-map
                    (kbd "C-t") #'my/ghostel-fresh
                    (kbd "C-<tab>") #'ghostel-next
                    (kbd "C-S-<tab>") #'ghostel-previous
                    (kbd "C-<iso-lefttab>") #'ghostel-previous
                    ;; Follow the hyperlink at point (OSC 8, auto-detected URL,
                    ;; or file:line ref).  Ghostel only binds RET-to-open in its
                    ;; read-only mode map; in evil normal-state scrollback RET is
                    ;; otherwise `evil-ret', so bind it here.  Off a link this is
                    ;; a no-op (ghostel-open-link-at-point does nothing).
                    (kbd "RET") #'ghostel-open-link-at-point
                    ;; Jump between links, vim-style (cf. ]q/[q).  C-c C-n/C-p
                    ;; still work too (evil doesn't shadow C-c).
                    (kbd "]l") #'ghostel-next-hyperlink
                    (kbd "[l") #'ghostel-previous-hyperlink))

;; ==========================================================================
;; 2.5 Browse scrollback without the viewport snapping back to the bottom
;; ==========================================================================

;; Ghostel auto-follows live output: on every redraw it re-anchors any window
;; still sitting at the bottom (`ghostel--window-anchored-p'), so when a command
;; finishes the screen jumps back down — annoying while reading scrollback.
;; Ghostel already ships the right escape hatch: `ghostel-emacs-mode' makes the
;; buffer read-only and STOPS auto-following while the terminal keeps running
;; and scrollback keeps growing (unlike `ghostel-copy-mode', which freezes
;; output entirely).
;;
;; We tie that mode to evil's editing state so it needs no separate muscle
;; memory: evil *normal* state == read-only "browse" (output streams in but the
;; viewport stays put), evil *insert* state == live terminal that follows the
;; output.  And since reaching for the wheel is itself a "let me look back"
;; gesture, scrolling up drops you into normal state automatically.
;;
;; All three are gated on `evil-ghostel--active-p' (a live shell prompt:
;; semi-char input mode, not an alt-screen TUI), so vim/htop and friends are
;; untouched — normal state and the wheel keep behaving as they do today there.

(defun my/ghostel-browse-on-normal ()
  "Enter ghostel's read-only `emacs' input mode on evil normal-state entry.
Only at a live shell prompt; there the terminal keeps streaming but ghostel
stops yanking the viewport to the bottom, so paging through scrollback stays
put.  Insert state restores the live following mode (`my/ghostel-follow-on-insert').
The entry message is suppressed since this fires on every drop to normal — the
`:Emacs' mode-line tag is indication enough."
  (when (evil-ghostel--active-p)
    (let ((inhibit-message t))
      (ghostel-emacs-mode))))

(defun my/ghostel-follow-on-insert ()
  "Leave ghostel's read-only `emacs' mode and resume the live terminal.
Installed at a low hook depth so it runs before evil-ghostel's own insert-entry
cursor sync, which only acts once the terminal is back in semi-char mode."
  (when (and (derived-mode-p 'ghostel-mode)
             (eq ghostel--input-mode 'emacs))
    (ghostel-semi-char-mode)))

(defun my/ghostel-wheel-browse (event)
  "Drop to evil normal state when scrolling up in a live ghostel terminal.
Entering normal state switches ghostel to the read-only `emacs' mode (via
`my/ghostel-browse-on-normal'), so a wheel-up into the scrollback no longer
snaps back on the next redraw.  Skips terminals tracking the mouse (TUIs like
vim/htop), where the wheel must reach the program.  EVENT is the wheel event;
run in the event's own buffer the way ghostel's own scroll intercept does."
  (with-current-buffer (window-buffer (posn-window (event-start event)))
    (when (and (evil-ghostel--active-p)
               (evil-insert-state-p)
               (not (ghostel--mouse-tracking-active-p)))
      (evil-normal-state))))

(with-eval-after-load 'evil-ghostel
  (add-hook 'ghostel-mode-hook
            (lambda ()
              (add-hook 'evil-normal-state-entry-hook
                        #'my/ghostel-browse-on-normal nil t)
              ;; Depth -90: run before evil-ghostel's own insert-entry hook so
              ;; the terminal is back in semi-char before that hook syncs the
              ;; cursor (it no-ops outside semi-char).
              (add-hook 'evil-insert-state-entry-hook
                        #'my/ghostel-follow-on-insert -90 t)))
  ;; `<wheel-up>'/`<mouse-4>' both dispatch through `ghostel--scroll-intercept-up';
  ;; advising it covers both.  :before so we switch state before the original
  ;; redispatches the event to the scroll handler.
  (advice-add 'ghostel--scroll-intercept-up :before #'my/ghostel-wheel-browse))

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
;; we wrap it (to record a jump, see below) and add split/vsplit variants for
;; `es'/`ev'.  Args arrive as strings.

;; Make C-o (`evil-jump-backward') return to the terminal after e/es/ev.
;; These openers run inside ghostel's VT parser (a process filter), NOT the
;; command loop, so evil's automatic buffer-crossing jump tracking never fires.
;; We therefore record the jump ourselves with `evil-set-jump' before opening.
;;
;; evil stores jumps by file name and only treats a *file-less* buffer (like our
;; terminals) as a jump target when its name matches `evil--jumps-buffer-targets'
;; — both when recording and when deciding `switch-to-buffer' vs `find-file' on
;; the way back.  The default only covers *new*/*scratch*, so extend it to also
;; match the "term: " prefix every terminal buffer carries (see section 1).
;; Safe: evil stores real files by ABSOLUTE path, which never begins with
;; "term:", so files keep round-tripping through `find-file'.
(with-eval-after-load 'evil
  (setq evil--jumps-buffer-targets
        (concat evil--jumps-buffer-targets "\\|\\`term:")))

(defun my/ghostel-set-jump ()
  "Record point in evil's jumplist, if evil is loaded.
Lets C-o return to the terminal after an e/es/ev file open."
  (when (fboundp 'evil-set-jump)
    (evil-set-jump)))

(defun my/ghostel-find-file (filename)
  "Open FILENAME in the current window, recording a jump first (vim :edit)."
  (my/ghostel-set-jump)
  (find-file filename))

(defun my/ghostel-find-file-split (filename)
  "Open FILENAME in a split below the terminal (vim :split)."
  (select-window (split-window-below))
  (my/ghostel-set-jump)        ; the new window still shows the terminal here
  (find-file filename))

(defun my/ghostel-find-file-vsplit (filename)
  "Open FILENAME in a split right of the terminal (vim :vsplit)."
  (select-window (split-window-right))
  (my/ghostel-set-jump)
  (find-file filename))

(with-eval-after-load 'ghostel
  ;; Swap the stock `find-file' (used by `e') for our jump-recording wrapper,
  ;; then add the split/vsplit variants.
  (setq ghostel-eval-cmds
        (cons '("find-file" my/ghostel-find-file)
              (assoc-delete-all "find-file" ghostel-eval-cmds)))
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
