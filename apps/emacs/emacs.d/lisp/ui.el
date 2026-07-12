;;; ui.el --- Frame chrome, line numbers, scrolling, font, theme  -*- lexical-binding: t; -*-

(menu-bar-mode 0)
(tool-bar-mode 0)
(scroll-bar-mode 0)

;; No audible or visible bell.  Instead of silencing the alert entirely, ask
;; the window manager to flag the Emacs window as demanding attention so
;; andrew-shell can surface it.  A ghostel terminal BEL reaches us via `ding'
;; (the native module's bell callback calls it), which runs `ring-bell-function'.
(defun my/frame-set-urgency (&optional frame)
  "Ask the window manager to flag FRAME as urgent / demanding attention.
Issues a window-activation request for FRAME via `x-focus-frame'.  On the Linux
pgtk (native Wayland) build this rides the `xdg-activation-v1' protocol, and
Hyprland translates an activation request for an *unfocused* window into its
urgent state — emitting an `urgent' IPC event andrew-shell reacts to — rather
than stealing focus (`misc:focus_on_activate' is off).

Gated to `pgtk' frames ONLY.  Elsewhere `x-focus-frame' has no such
urgent-instead-of-focus translation and would just raise/activate the frame:
on macOS (the `emacs-macport' build, whose frames are `mac') it would yank the
Emacs window to the foreground and steal focus — exactly what we don't want for
a background bell.  So this is a deliberate no-op off pgtk (macOS, TTY, …),
matching the original X-only guard's behaviour on those platforms.

We also don't poke WM_HINTS UrgencyHint (Hyprland's XWM ignores the bit) nor
hand-roll an `_NET_ACTIVE_WINDOW' client message: the latter needs
`x-send-client-message', which the pgtk build does not provide — its frames are
`pgtk', not `x', and expose no X window id (`outer-window-id' is nil), so the
old X-only path silently no-ops there."
  (let ((frame (or frame (selected-frame))))
    (when (eq (framep frame) 'pgtk)
      (x-focus-frame frame))))

(defun my/ring-bell-urgent ()
  "Silent bell that flags the frame urgent for ghostel terminal BELs.
ghostel has no dedicated bell hook — its native module just calls `ding' — but
its process filter feeds PTY output to the module inside `with-current-buffer'
on the terminal buffer (see `ghostel--filter'), so a terminal BEL reaches us
with that buffer current.  Gating on `ghostel-mode' therefore routes only
terminal bells to the urgency request; every other Emacs ding (evil failed
motions, errors, …) fires with some other buffer current and stays silent.
Also skip when Emacs already has focus: the bell is then just noise, and a
window manager only flags an *unfocused* window urgent anyway."
  (when (and (derived-mode-p 'ghostel-mode)
             (not (eq (frame-focus-state) t)))
    (my/frame-set-urgency)))

(setq ring-bell-function #'my/ring-bell-urgent)

(setq display-line-numbers-type 'relative)
;; Show line numbers only in code and text buffers, not in special buffers like
;; neotree, ghostel terminals, magit, dired, etc.  (Enabling globally and trying
;; to exclude per-mode is fragile: `global-display-line-numbers-mode' re-enables
;; numbers *after* a mode's own hook runs, so a buffer-local disable in, say,
;; `ghostel-mode-hook' would just get overridden.  Opting in per-mode avoids
;; that fight entirely — neotree/ghostel aren't derived from prog/text-mode.)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'text-mode-hook #'display-line-numbers-mode)

;; --- Git change markers in the fringe (gitsigns equivalent) -----------------
;; Added/changed/deleted indicators next to the line numbers in every
;; version-controlled buffer.  flydiff refreshes them as you type instead of
;; only on save; the magit hooks keep them in sync when a stage/commit happens
;; (diffview shells through magit, so it's covered too).
(global-diff-hl-mode 1)
(diff-hl-flydiff-mode 1)
(add-hook 'magit-pre-refresh-hook  #'diff-hl-magit-pre-refresh)
(add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)

;; --- Smooth scrolling ------------------------------------------------------
;; Pixel-precision scrolling for the mouse/trackpad (built into Emacs 29+):
;; the view glides by pixels instead of jumping a whole line at a time.
(pixel-scroll-precision-mode 1)
;; Animate full-page jumps (C-v / M-v) too.
(setq pixel-scroll-precision-interpolate-page t)
;; Keep *keyboard* scrolling smooth: scroll just enough to keep point on screen
;; (>100 disables the jarring recenter), keeping a few lines of context around
;; point so it never sits glued to the very top/bottom edge.
(setq scroll-conservatively 101
      scroll-margin 3
      scroll-step 1)

(set-face-attribute 'default nil
		    :font "BerkeleyMono Nerd Font"
		    :height (if (eq system-type 'darwin) 150 110)
		    :weight 'normal)

(load-theme 'kanagawa-wave t)

;;; ui.el ends here
