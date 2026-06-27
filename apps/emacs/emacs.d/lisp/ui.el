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
Sends an EWMH `_NET_ACTIVE_WINDOW' client message to the root window targeting
FRAME's window.  Hyprland translates an activation request for an *unfocused*
window into its urgent state — emitting an `urgent' IPC event andrew-shell can
react to — rather than stealing focus (`misc:focus_on_activate' is off).

We deliberately do NOT use the older ICCCM WM_HINTS UrgencyHint: Hyprland's
XWayland reads WM_HINTS but ignores the urgency bit entirely (see
`handleWMHints' in its XWM), so setting it does nothing.  `_NET_ACTIVE_WINDOW'
is the only signal it honours.  No-op on non-X frames (e.g. batch/TTY).

DEST 0 means the root window; Emacs fills the event's target-window field with
FRAME's outer window.  The data list is the EWMH source indication (1 =
application) plus unused timestamp/requestor slots — Hyprland ignores the
payload, but we send a well-formed message anyway."
  (let ((frame (or frame (selected-frame))))
    (when (eq (framep frame) 'x)
      (x-send-client-message nil 0 frame "_NET_ACTIVE_WINDOW" 32 '(1 0 0)))))

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
