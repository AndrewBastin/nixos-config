;;; ghostel.el --- Ghostel terminal: evil integration, openers, file shim, startup banner  -*- lexical-binding: t; -*-

;; ==========================================================================
;; 1. Core setup: evil integration, escape behaviour
;; ==========================================================================

;; The native module ships bundled next to ghostel.el (built from the same rev by
;; packages/ghostel), which is the loader's default location, so
;; `ghostel-module-directory' is left nil and ghostel finds the module on its own.

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
             ;; `ghostel--title' is the buffer-local cache of the last OSC 0/2
             ;; title report (ghostel core keeps it in sync via `ghostel--set-title').
             ;; Ghostel's own `ghostel--update-directory' recomputes the name the
             ;; same way; we mirror it here for the command start/finish markers.
             (ghostel--rename-managed
              (funcall ghostel-buffer-name-function ghostel--title)))))))))

(with-eval-after-load 'ghostel
  (add-hook 'ghostel-command-start-functions  #'my/ghostel-refresh-name)
  (add-hook 'ghostel-command-finish-functions #'my/ghostel-refresh-name))

;; ==========================================================================
;; 2. Clipboard paste + evil-ghostel key bindings
;; ==========================================================================

;; Paste the *system clipboard* (not the kill ring) into the terminal, bound to
;; C-S-v below.  We read the CLIPBOARD selection directly so it works regardless
;; of the kill-ring state, and send it via `ghostel-paste-string' which wraps it
;; in bracketed paste so the shell sees it as pasted rather than typed.
;;
;; Read via `gui--selection-value-internal' — the same value primitive evil's
;; "+ register and `gui-selection-value' (normal yank) use — NOT a bare
;; `gui-get-selection'.  On the emacs-mac port (Darwin) `gui-get-selection'
;; defaults its target to `STRING', which the port answers with nil (it exposes
;; the pasteboard string only under `NSStringPboardType'), so the old code
;; wrongly reported "System clipboard is empty".  The value primitive knows the
;; port's own accessor and returns the text on both mac and pgtk; unlike
;; `gui-selection-value' it does NOT suppress a clipboard Emacs itself set, so
;; pasting text you just yanked in Emacs into the terminal still works.
(defun my/ghostel-clipboard-text ()
  "Return the system clipboard as a plain string, or nil if empty."
  (let ((text (gui--selection-value-internal 'CLIPBOARD)))
    (and text (not (string-empty-p text)) (substring-no-properties text))))

(defun my/ghostel-paste-clipboard ()
  "Paste the system clipboard into the ghostel terminal (bracketed paste)."
  (interactive)
  (let ((text (my/ghostel-clipboard-text)))
    (if text
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
;; All three are gated on `evil-ghostel--prompt-active-p' (a live shell prompt:
;; semi-char input mode, not an alt-screen TUI), so vim/htop and friends are
;; untouched — normal state and the wheel keep behaving as they do today there.

(declare-function evil-ghostel--prompt-active-p "evil-ghostel")

(defun my/ghostel-browse-on-normal ()
  "Enter ghostel's read-only `emacs' input mode on evil normal-state entry.
Only at a live shell prompt; there the terminal keeps streaming but ghostel
stops yanking the viewport to the bottom, so paging through scrollback stays
put.  Insert state restores the live following mode (`my/ghostel-follow-on-insert').
The entry message is suppressed since this fires on every drop to normal — the
`:Emacs' mode-line tag is indication enough."
  (when (evil-ghostel--prompt-active-p)
    (let ((inhibit-message t))
      (ghostel-emacs-mode))))

(defun my/ghostel-follow-on-insert ()
  "Leave ghostel's read-only `emacs' mode and resume the live terminal.
Installed at a low hook depth so it runs before evil-ghostel's own insert-entry
cursor sync, which only acts once the terminal is back in semi-char mode."
  (when (and (derived-mode-p 'ghostel-mode)
             (eq ghostel--input-mode 'emacs))
    (ghostel-semi-char-mode)))

;; Ghostel <= 0.39 (elpa 20260626) shipped `ghostel--mouse-tracking-active-p';
;; later builds (20260706+) dropped that wrapper and fold the check into
;; `ghostel--mouse-event'/`ghostel--forward-scroll-event', which *send* the
;; event as a side effect and so can't be used as a pure predicate.  The native
;; `ghostel--mode-enabled' primitive (used by ghostel itself) is stable across
;; both, so we reimplement the tiny predicate here — matching what the removed
;; upstream defun did — to stay decoupled from that elisp rename.
(declare-function ghostel--mode-enabled "ghostel-module")

(defun my/ghostel--mouse-tracking-active-p ()
  "Non-nil if this ghostel terminal has any DEC mouse-tracking mode set.
Checks modes 1000 (normal), 1002 (button-event) and 1003 (any-event) — the
modes a TUI enables when it wants to consume mouse input itself."
  (and (bound-and-true-p ghostel--term)
       (or (ghostel--mode-enabled ghostel--term 1000)
           (ghostel--mode-enabled ghostel--term 1002)
           (ghostel--mode-enabled ghostel--term 1003))))

(defun my/ghostel-wheel-browse (event)
  "Drop to evil normal state when scrolling up in a live ghostel terminal.
Entering normal state switches ghostel to the read-only `emacs' mode (via
`my/ghostel-browse-on-normal'), so a wheel-up into the scrollback no longer
snaps back on the next redraw.  Skips terminals tracking the mouse (TUIs like
vim/htop), where the wheel must reach the program.  EVENT is the wheel event;
run in the event's own buffer the way ghostel's own scroll intercept does."
  (with-current-buffer (window-buffer (posn-window (event-start event)))
    (when (and (evil-ghostel--prompt-active-p)
               (evil-insert-state-p)
               (not (my/ghostel--mouse-tracking-active-p)))
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
;;
;; Each opener binds `default-directory' to `my/active-dir' (defined in §4.5)
;; around the spawn so the new terminal starts in the active working dir — the
;; pin if set, else the focused terminal's cwd, else the current buffer's dir —
;; matching how SPC f / SPC gp / neotree already resolve their directory.
(defun my/ghostel-fresh ()
  "Open a brand-new Ghostel terminal in the current window."
  (interactive)
  (let ((default-directory (my/active-dir)))
    (ghostel '(4))))

(defun my/ghostel-split ()
  "Open a fresh Ghostel terminal in a new split below (vim :split)."
  (interactive)
  (select-window (split-window-below))
  (let ((default-directory (my/active-dir)))
    (ghostel '(4))))

(defun my/ghostel-vsplit ()
  "Open a fresh Ghostel terminal in a new split to the right (vim :vsplit)."
  (interactive)
  (select-window (split-window-right))
  (let ((default-directory (my/active-dir)))
    (ghostel '(4))))

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
  (add-to-list 'ghostel-eval-cmds '("find-file-vsplit" my/ghostel-find-file-vsplit))
  ;; Working-directory pin/unpin (handlers defined in section 4.5).
  (add-to-list 'ghostel-eval-cmds '("pin"   my/pin-dir))
  (add-to-list 'ghostel-eval-cmds '("unpin" my/unpin-dir)))

;; ==========================================================================
;; 4.5 Working directory: follow the focused terminal, with pin/unpin
;; ==========================================================================

;; The config is terminal-driven: you `cd' into a project in a ghostel terminal,
;; then open and search files.  But each directory-sensitive command used to
;; derive its OWN "current folder" — neotree froze on whatever root it first
;; opened with, and `consult-fd' (SPC f) drifted to the parent of whichever file
;; you last opened.  Unify them on ONE source of truth: the focused terminal's
;; cwd, with an explicit `pin' override.
;;
;; `my/active-project-dir' resolves, in order: an explicit pin; else the live
;; `default-directory' of the most-recently-focused ghostel buffer; else nil
;; (defer to normal per-file VCS detection — nothing pinned and no terminal live).

(defvar my/pinned-dir nil
  "Explicitly pinned working directory, or nil to follow the focused terminal.
Set/cleared by the `pin'/`unpin' shell commands (whitelisted in section 4).")

(defvar my/last-ghostel-buffer nil
  "Most-recently-focused ghostel buffer; the follow source for `my/active-project-dir'.")

(defun my/active-project-dir ()
  "Directory to treat as the project root, or nil to defer to normal detection.
The pin wins; otherwise the focused terminal's cwd; otherwise nil."
  (cond (my/pinned-dir)
        ((buffer-live-p my/last-ghostel-buffer)
         (buffer-local-value 'default-directory my/last-ghostel-buffer))))

(defun my/active-dir ()
  "Like `my/active-project-dir' but never nil — falls back to `default-directory'."
  (or (my/active-project-dir) default-directory))

;; --- Route project-aware commands through the active dir ------------------
;; `consult-fd' (SPC f) and `consult-ripgrep' (SPC gp) default their search dir
;; to (or (consult--project-root) default-directory), and `project-find-file'
;; (SPC SPC) calls `project-current' directly — so ONE `project.el' backend
;; steers all three (plus the project consult-buffer source), no rebinding.
;; When the active dir is exactly a VC root we hand back the VC project (fast
;; `git ls-files' listing); otherwise a `transient' project pinned to that exact
;; dir.  nil ⇒ this backend bows out and stock `project-try-vc' runs as before.
;;
;; CRUCIALLY this bows out under `eglot-lsp-context' (which eglot binds while it
;; calls `project-current'): an LSP server like rust-analyzer must root at the
;; real *language* project (the nearest Cargo.toml), NOT the pinned/terminal
;; working dir — so eglot's root detection is left to `my/eglot-project' (ide.el)
;; and `project-try-vc'.  This is the navigation/LSP split nvim gets for free
;; (telescope follows cwd; lspconfig uses root_pattern).
(defun my/active-project (_dir)
  "A `project-find-functions' entry returning the active dir as a project.
Yields to normal detection while eglot is resolving its LSP root."
  (unless (bound-and-true-p eglot-lsp-context)
    (when-let* ((d (my/active-project-dir))
                (d (file-name-as-directory (expand-file-name d))))
      (or (when-let* ((vc (project-try-vc d))
                      ((equal (file-name-as-directory (expand-file-name (project-root vc))) d)))
            vc)
          (cons 'transient d)))))

(with-eval-after-load 'project
  (add-to-list 'project-find-functions #'my/active-project))

;; --- neotree follows the active dir ---------------------------------------
(defun my/neotree-toggle ()
  "Toggle the neotree window; when opening, root it at the active dir."
  (interactive)
  (require 'neotree)   ; only `neotree-dir'/-toggle autoload; we use internals below
  (if (neo-global--window-exists-p)
      (neotree-hide)
    (neotree-dir (my/active-dir))))

(defun my/neotree-follow (&rest _)
  "Re-root an already-open neotree window to the active dir, without stealing focus.
No-op when neotree is closed, or when nothing is pinned/followed (so plain buffer
switches don't move the tree).  The actual re-root is deferred via a timer so it
never runs inside ghostel's VT parser, and only fires when the root truly differs."
  (when (and (fboundp 'neo-global--window-exists-p)
             (neo-global--window-exists-p))
    (when-let* ((target (my/active-project-dir))
                (target (file-name-as-directory (expand-file-name target)))
                (nbuf (neo-global--get-buffer))
                (root (buffer-local-value 'neo-buffer--start-node nbuf)))
      (unless (equal target (file-name-as-directory (expand-file-name root)))
        (run-at-time 0 nil
                     (lambda ()
                       (when (neo-global--window-exists-p)
                         (save-selected-window (neotree-dir target)))))))))

;; --- Track the focused terminal -------------------------------------------
;; Record the ghostel buffer whenever one becomes the selected window's buffer,
;; then let neotree follow.  Both hooks pass the affected frame: selection-change
;; covers focusing another window; buffer-change covers swapping a window's
;; buffer to a terminal in place (e.g. cycling with C-<tab>).
(defun my/track-ghostel-focus (frame)
  "Note the focused ghostel buffer (if any) and let neotree follow it."
  (when (frame-live-p frame)
    (let ((buf (window-buffer (frame-selected-window frame))))
      (when (and (buffer-live-p buf)
                 (provided-mode-derived-p
                  (buffer-local-value 'major-mode buf) 'ghostel-mode))
        (setq my/last-ghostel-buffer buf)))
    (my/neotree-follow)))

(add-hook 'window-selection-change-functions #'my/track-ghostel-focus)
(add-hook 'window-buffer-change-functions    #'my/track-ghostel-focus)

;; --- Follow a `cd' inside the focused terminal ----------------------------
;; ghostel's OSC 7 handler updates the terminal buffer's `default-directory' and
;; THEN calls `ghostel-buffer-name-function' (ghostel core) — the one reliable
;; post-cwd seam (`ghostel-command-finish-functions' fires before the prompt
;; re-reports the cwd).  Wrap our namer (section 1) so it also nudges neotree
;; when the *focused* terminal's cwd changes.
(defun my/ghostel-name+follow (title)
  "Compute the managed ghostel name (`my/ghostel-buffer-name'), then follow cwd."
  (prog1 (my/ghostel-buffer-name title)
    (when (eq (current-buffer) my/last-ghostel-buffer)
      (my/neotree-follow))))

(setq ghostel-buffer-name-function #'my/ghostel-name+follow)

;; --- pin / unpin handlers (whitelisted in section 4) ----------------------
(defun my/pin-dir (dir)
  "Pin DIR as the working directory, overriding terminal-follow (the `pin' command)."
  (setq my/pinned-dir (file-name-as-directory (expand-file-name dir)))
  (message "Pinned working dir: %s" (abbreviate-file-name my/pinned-dir))
  (my/neotree-follow))

(defun my/unpin-dir (&rest _)
  "Clear the pin and resume following the focused terminal (the `unpin' command)."
  (setq my/pinned-dir nil)
  (message "Unpinned — following the focused terminal")
  (my/neotree-follow))

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
  "Redirect EMACS_GHOSTEL_PATH to a shim that adds `e'/`es'/`ev'/`pin'/`unpin'.
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
           "ev() { ghostel_cmd find-file-vsplit \"${1:a}\"; }\n"
           ;; pin [DIR]: freeze the working dir Emacs uses (neotree, SPC f/gp/SPC).
           ;; No arg → current shell dir; `:a' absolutises against the shell cwd so
           ;; a relative DIR resolves regardless of Emacs's `default-directory'.
           ;; unpin: resume following the focused terminal.
           "pin()   { local d=${1:-$PWD}; ghostel_cmd pin \"${d:a}\"; }\n"
           "unpin() { ghostel_cmd unpin; }\n"
           ;; AI-agent integration (lisp/agent.el): wrap `claude' so every
           ;; invocation — including via the clod/migu aliases — carries the
           ;; Emacs capability briefing.  Baked in at spawn time; fboundp-guarded
           ;; so a load-order hiccup degrades to a plain shim, not an error.
           (if (fboundp 'my/agent-shim-snippet) (my/agent-shim-snippet) "")))
        (setenv "EMACS_GHOSTEL_PATH" my/ghostel-shim-dir)))))

(add-hook 'ghostel-pre-spawn-hook #'my/ghostel-install-shell-shim)

;; Point $EDITOR at a blocking emacsclient aimed at THIS Emacs's uniquely-named
;; server (section 6) for every ghostel-spawned shell, so jj/jjui/git/
;; edit-command-line — anything honouring $EDITOR — edits in the Emacs that owns
;; the terminal.  A plain `setenv' in `ghostel-pre-spawn-hook' rewrites only the
;; about-to-spawn child's env (process-environment is dynamically bound there),
;; like the EMACS_GHOSTEL_PATH rewrite above — so the override is scoped to
;; ghostel terminals and never leaks to the global $EDITOR (nvim) outside Emacs.
;; The nix side defaults $EDITOR to `${EDITOR:-nvim}' (modules/dev-essentials) so
;; the child's own .zshenv respects this inherited value instead of clobbering it.
;;
;; DARWIN CAVEAT: `my/ghostel-force-env-repair' below clears nix-darwin's
;; set-environment guards so /etc/zshenv re-runs `set-environment' to repair
;; PATH — but that script also does an UNCONDITIONAL `export EDITOR="nano"',
;; which wipes the value we set here BEFORE ~/.zshenv even runs (so ~/.zshenv's
;; `nano'->`nvim' default then wins and every ghostel terminal ends up on nvim,
;; breaking jj/jjui/git/edit-command-line).  set-environment leaves unknown vars
;; alone, so we ALSO stash the value in `EMACSCLIENT_EDITOR'; the home-manager
;; .zshenv (modules/dev-essentials) restores $EDITOR from it after /etc/zshenv,
;; undoing the clobber.  On Linux the guards are never cleared, so nothing
;; clobbers $EDITOR and the restore is a harmless no-op (the sentinel already
;; equals $EDITOR).
(defun my/ghostel-set-editor-env ()
  "Set $EDITOR to THIS Emacs's blocking emacsclient, for ghostel shells only."
  (let ((editor (format "emacsclient --socket-name=%s" my/ghostel-server-name)))
    (setenv "EDITOR" editor)
    (setenv "EMACSCLIENT_EDITOR" editor)))

(add-hook 'ghostel-pre-spawn-hook #'my/ghostel-set-editor-env)

;; Expose this Emacs's server socket to every ghostel shell.  `emacsclient'
;; reads $EMACS_SOCKET_NAME natively (same resolution as --socket-name), so
;; agents briefed by lisp/agent.el reach the OWNING Emacs with a bare
;; `emacsclient -e ...' — and the var doubles as the honest "this shell lives
;; inside an Emacs session" marker.  Scoped to the child via the dynamically
;; bound `process-environment', like the $EDITOR rewrite above.  nix-darwin's
;; set-environment repair (see `my/ghostel-force-env-repair') leaves unknown
;; vars alone, so this survives the darwin env repair.
(defun my/ghostel-set-agent-env ()
  "Set $EMACS_SOCKET_NAME to this Emacs's server socket, for ghostel shells."
  (setenv "EMACS_SOCKET_NAME" my/ghostel-server-name))

(add-hook 'ghostel-pre-spawn-hook #'my/ghostel-set-agent-env)

;; A GUI-launched Emacs.app (alt-y → emacs-gui → `open -a Emacs.app') does NOT
;; inherit the login shell's PATH — macOS hands it launchd's minimal PATH, so
;; the nix profile dirs (/etc/profiles/per-user/$USER/bin, /run/current-system/
;; sw/bin) where zoxide/claude/node/etc. live are absent.  Ghostel shells
;; normally recover because nix-darwin's /etc/zshenv re-runs `set-environment',
;; which overwrites PATH with the correct profile dirs — BUT that repair is
;; guarded:
;;
;;   if [[ -o rcs ]]; then
;;     if [ -z "${__NIX_DARWIN_SET_ENVIRONMENT_DONE-}" ]; then . set-environment; fi
;;
;; and /etc/zshenv itself returns early on `__ETC_ZSHENV_SOURCED'.  If Emacs is
;; launched from a context that already exported either guard, the repair is
;; skipped and the impoverished GUI PATH leaks into every ghostel shell —
;; `zoxide'/`claude' vanish and the `clod'/`migu' aliases expand to a missing
;; binary.  Clearing both guards in the about-to-spawn child env forces the
;; repair to run for every ghostel shell regardless of how Emacs was launched
;; (`set-environment' is idempotent — it re-sets a fixed PATH, and also
;; re-exports EDITOR/PAGER; see `my/ghostel-set-editor-env' for how the EDITOR
;; override is stashed and restored around this clobber).  Like the
;; EDITOR/EMACS_GHOSTEL_PATH rewrites above, the `setenv' is scoped to the child
;; via the dynamically-bound `process-environment', so the global env is
;; untouched.  Darwin-only: these guards are nix-darwin's, and the GUI-PATH
;; problem they work around doesn't exist on Linux.
(defun my/ghostel-force-env-repair ()
  "Clear nix-darwin's set-environment guards so /etc/zshenv re-repairs PATH."
  (setenv "__NIX_DARWIN_SET_ENVIRONMENT_DONE" nil)
  (setenv "__ETC_ZSHENV_SOURCED" nil))

(when (eq system-type 'darwin)
  (add-hook 'ghostel-pre-spawn-hook #'my/ghostel-force-env-repair))

;; ==========================================================================
;; 6. Blocking editor for terminal programs ($EDITOR via `emacsclient')
;; ==========================================================================

;; The e/es/ev openers above are non-blocking: they pop the file and return
;; immediately, so they can't serve as a program's $EDITOR (jj/git must block
;; until the message is written and saved).  `emacsclient' is the blocking
;; counterpart — it opens the file in THIS Emacs (the one hosting the ghostel
;; terminal) and waits until the edit is finished with `with-editor-finish'
;; (C-c C-c / :wq — see the with-editor setup below).
;;
;; Each Emacs runs its server under a UNIQUE name `ghostel-<pid>' rather than the
;; shared default "server".  With the default name, a SECOND Emacs would see the
;; first's socket via `server-running-p' and skip starting its own — so its
;; ghostel terminals' emacsclient would connect to the FIRST Emacs (wrong
;; instance).  A per-pid name gives every instance its own socket; section 5 sets
;; each ghostel shell's $EDITOR to `emacsclient --socket-name=<this name>'
;; directly, so jj/jjui/git/edit-command-line edit in the OWNING Emacs.  `emacs-pid' is unique
;; among live processes; a stale socket from a dead same-pid Emacs is cleaned up
;; by `server-start' before it binds.
(defvar my/ghostel-server-name (format "ghostel-%d" (emacs-pid))
  "Unique `server-name' for this Emacs instance.
Computed once at load so the same name is baked into the $EDITOR=`emacsclient
--socket-name=…' that section 5 hands each ghostel shell.")

(require 'server)
(require 'with-editor)
(setq server-name my/ghostel-server-name)
(unless (server-running-p) (server-start))

;; emacsclient buffers (jj/jjui commit descriptions, git commit messages,
;; edit-command-line, …) open in a split below the ghostel terminal — same
;; `:split' geometry as the `es' opener — instead of clobbering the terminal's
;; own window.  `with-editor-mode' (magit's editor package) owns the finish/
;; cancel UX so we don't hand-roll it:
;;   C-c C-c / :wq / :x / ZZ  -> `with-editor-finish' — save, then `server-done'
;;                               to unblock the waiting program (jj/git/…).
;;   C-c C-k / :q  / ZQ       -> `with-editor-cancel' — the client exits non-zero
;;                               so jj/git DISCARDS the commit (a real abort, which
;;                               the old hand-rolled `:wq'-only setup couldn't do).
;; with-editor's keymap remaps evil's `evil-save-and-close' /
;; `evil-save-modified-and-close' / `evil-quit', and `evil-ex-binding' honours
;; `command-remapping', so the vim ex-commands route to finish/cancel with no
;; per-buffer ex rebinding.  It also reroutes a stray `kill-buffer' to cancel,
;; so a blocked jj/git is never left hanging.
;;
;; `server-window' takes the emacsclient buffer and must display+select it.  We
;; snapshot the pre-split window layout into `with-editor-previous-winconf'
;; (buffer-local); with-editor restores it on finish/cancel, returning the
;; terminal to full height.  This fires for any $EDITOR-driven edit from a
;; ghostel shell — the only thing that reaches this Emacs's per-pid server,
;; since e/es/ev use ghostel's OSC-52 path, not emacsclient.  `with-editor-mode'
;; is `:interactive nil'; calling it non-interactively here is the supported way
;; to enable it on a server buffer.
(setq server-window
      (lambda (buffer)
        (let ((winconf (current-window-configuration)))
          (select-window (split-window-below))
          (switch-to-buffer buffer)
          (with-editor-mode 1)
          (setq with-editor-previous-winconf winconf))))

;; Syntax highlighting for jj's `*.jjdescription' commit-message files is
;; provided by the `jjdescription' package (installed in apps/emacs/default.nix),
;; which autoloads its own `auto-mode-alist' entry — nothing to wire up here.

;; ==========================================================================
;; 7. Startup banner
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
