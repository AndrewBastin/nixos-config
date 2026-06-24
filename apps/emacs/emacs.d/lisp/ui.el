;;; ui.el --- Frame chrome, line numbers, scrolling, font, theme  -*- lexical-binding: t; -*-

(menu-bar-mode 0)
(tool-bar-mode 0)
(scroll-bar-mode 0)

;; No audible or visible bell — silence the alert entirely.
(setq ring-bell-function 'ignore)

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
		    :height (if (eq system-type 'darwin) 150 180)
		    :weight 'normal)

(load-theme 'kanagawa-wave t)

;;; ui.el ends here
