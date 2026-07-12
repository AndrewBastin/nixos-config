;;; init.el --- Load the modular config from lisp/  -*- lexical-binding: t; -*-

;; Modules are loaded BY ABSOLUTE PATH (not require/load-path) so there is no
;; load-path search and thus no shadowing of real package features (evil,
;; ghostel).  `my/config-dir' is the read-only store path captured in
;; early-init.el.  Order is significant: evil before modeline/keybindings,
;; ghostel before keybindings.
(dolist (m '("defaults" "ui" "evil" "vc" "modeline" "completion" "ide" "markdown" "ghostel" "diffview" "keybindings"))
  (load (expand-file-name (concat "lisp/" m) my/config-dir) nil t))

;;; init.el ends here
