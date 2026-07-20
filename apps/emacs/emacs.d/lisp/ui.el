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

;; --- Transparent titlebar (macOS) -------------------------------------------
;; Blend the titlebar into the theme background instead of macOS's opaque gray
;; bar.  The Mac port (emacs-macport) has no `ns-transparent-titlebar' frame
;; parameter (that's the NS/Cocoa build) and no source-level support at all, so
;; instead of patching macappkit.m (a full Emacs rebuild to maintain across
;; macport bumps) we flip NSWindow.titlebarAppearsTransparent from inside the
;; running process via `mac-osa-script''s JXA ObjC bridge.  The titlebar then
;; shows NSWindow.backgroundColor, which the Mac port already keeps in sync
;; with the frame's background color, so it matches the theme with no extra
;; work.
;;
;; The title TEXT color is a different mechanism: AppKit picks it from the
;; window's NSAppearance, which by default follows the *system* appearance —
;; system dark mode + a light theme (kanagawa-lotus) would give white-on-cream
;; text.  So we also pin each window's appearance (Aqua/DarkAqua) to the
;; frame background's relative luminance, the macport equivalent of the NS
;; build's `ns-appearance' frame parameter.
(defun my/mac-transparent-titlebar (&optional frame-or-theme)
  "Give every Emacs NSWindow a transparent, theme-matched titlebar.
Sets `titlebarAppearsTransparent' and pins the window appearance to
Aqua/DarkAqua depending on whether the frame background is light or dark, so
the title text stays readable on both.  Acts on ALL of the app's windows (not
just one frame's): the properties are idempotent, and matching a specific
frame to its NSWindow through the OSA bridge is not worth the trouble.

FRAME-OR-THEME absorbs whatever the calling hook passes: a frame from
`after-make-frame-functions', a theme symbol from `enable-theme-functions' /
`disable-theme-functions', or nil from `window-setup-hook'.  Anything that
isn't a frame means \"use the selected frame\".  Only `mac' frames act, so TTY
frames and other builds no-op.  Wrapped in `ignore-errors' so an OSA hiccup
can never break frame creation or a theme switch."
  (let ((frame (if (framep frame-or-theme) frame-or-theme (selected-frame))))
    (when (and (eq (framep frame) 'mac)
               (fboundp 'mac-osa-script))
      (ignore-errors
        (let* ((rgb (color-name-to-rgb
                     (frame-parameter frame 'background-color) frame))
               ;; ITU-R BT.709 relative luminance, same formula color.el uses.
               (light (and rgb
                           (> (+ (* 0.2126 (nth 0 rgb))
                                 (* 0.7152 (nth 1 rgb))
                                 (* 0.0722 (nth 2 rgb)))
                              0.5))))
          (mac-osa-script
           (format "ObjC.import('AppKit');
                    var ap = $.NSAppearance.appearanceNamed($.%s);
                    var wins = $.NSApplication.sharedApplication.windows;
                    for (var i = 0; i < wins.count; i++) {
                      var w = wins.objectAtIndex(i);
                      w.titlebarAppearsTransparent = true;
                      w.appearance = ap;
                    }"
                   (if light "NSAppearanceNameAqua" "NSAppearanceNameDarkAqua"))
           "JavaScript"))))))

;; Initial frame exists by `window-setup-hook'; later frames (make-frame,
;; emacsclient -c) come through `after-make-frame-functions'; theme switches
;; change the background color and thus possibly the light/dark side, so
;; re-sync on enable AND disable (disabling a theme reverts the background).
(add-hook 'window-setup-hook #'my/mac-transparent-titlebar)
(add-hook 'after-make-frame-functions #'my/mac-transparent-titlebar)
(add-hook 'enable-theme-functions #'my/mac-transparent-titlebar)
(add-hook 'disable-theme-functions #'my/mac-transparent-titlebar)

(set-face-attribute 'default nil
		    :font "BerkeleyMono Nerd Font"
		    :height (if (eq system-type 'darwin) 150 110)
		    :weight 'normal)

(load-theme 'kanagawa-wave t)

;;; ui.el ends here
