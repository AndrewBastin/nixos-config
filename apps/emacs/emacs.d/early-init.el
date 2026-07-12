;;; early-init.el --- writable-state redirects for a store-baked config -*- lexical-binding: t; -*-

;; This config is baked READ-ONLY into the Nix store; `user-emacs-directory'
;; (set by --init-directory to the store path) must not be written to.  We
;; capture the store dir for reading bundled files, then point every writable
;; thing at XDG cache/state so nothing lands in the store or next to source
;; files (keeps version control clean).

;; --- GC & subprocess I/O tuning ----------------------------------------------
;; The default `gc-cons-threshold' (800KB) makes allocation-heavy work (LSP
;; JSON parsing, corfu) collect constantly: measured on this build (Emacs
;; 30.2), one collection pauses ~13ms, and an allocation-churn benchmark ran
;; 66 collections at the default vs 4 at 32MB — 3.5x slower wall-clock.  32MB
;; keeps pauses rare without hoarding memory.  (No separate startup dance:
;; Emacs 30 already runs init at `gc-cons-percentage' 1.0 and restores it.)
(setq gc-cons-threshold (* 32 1024 1024))

;; Max bytes read from a subprocess per chunk — also the pipe size Emacs
;; requests via F_SETPIPE_SZ.  The 64KB default fragments rust-analyzer's
;; multi-megabyte LSP responses; 1MB is the kernel's unprivileged pipe cap
;; (/proc/sys/fs/pipe-max-size), so asking for more buys nothing.
(setq read-process-output-max (* 1024 1024))

(defun my/xdg (env fallback)
  "Return the absolute dir for XDG ENV, or FALLBACK (expanded) if unset/relative."
  (let ((v (getenv env)))
    (if (and v (file-name-absolute-p v)) v (expand-file-name fallback))))

;; Remember the read-only store config dir (init.el reads banner.txt from here).
(defvar my/config-dir user-emacs-directory
  "The read-only Nix-store directory this config was loaded from.")

(defconst my/cache-dir (expand-file-name "emacs/" (my/xdg "XDG_CACHE_HOME" "~/.cache")))
(defconst my/state-dir (expand-file-name "emacs/" (my/xdg "XDG_STATE_HOME" "~/.local/state")))
(defconst my/data-dir  (expand-file-name "emacs/" (my/xdg "XDG_DATA_HOME"  "~/.local/share")))

(dolist (d (list my/cache-dir my/state-dir my/data-dir))
  (make-directory d t))

;; Catch-all: anything user-emacs-directory-relative we forget lands in writable
;; STATE rather than failing against the read-only store.  The ghostel shim
;; init.el generates under user-emacs-directory follows this automatically.
(setq user-emacs-directory my/state-dir)

;; Native-comp eln-cache -> CACHE.  Must be redirected here, in early-init.
(when (and (fboundp 'startup-redirect-eln-cache)
           (fboundp 'native-comp-available-p)
           (native-comp-available-p))
  (startup-redirect-eln-cache
   (convert-standard-filename (expand-file-name "eln-cache/" my/cache-dir))))

;; --- Next-to-file artifacts -> CACHE ----------------------------------------
;; Trailing t = UNIQUIFY: flatten the full path to "!"-separated names so two
;; files sharing a basename never collide in the central dir.
(let ((backup   (expand-file-name "backup/"    my/cache-dir))
      (autosave (expand-file-name "auto-save/" my/cache-dir))
      (lockdir  (expand-file-name "lock/"      my/cache-dir)))
  (dolist (d (list backup autosave lockdir)) (make-directory d t))
  (setq backup-directory-alist         `(("." . ,backup))
        auto-save-file-name-transforms `((".*" ,autosave t))
        lock-file-name-transforms      `((".*" ,lockdir  t))
        auto-save-list-file-prefix     (expand-file-name "auto-save-list/.saves-" my/cache-dir)))

;; --- Persistent history -> STATE --------------------------------------------
(setq recentf-save-file     (expand-file-name "recentf"   my/state-dir)
      savehist-file         (expand-file-name "savehist"  my/state-dir)
      save-place-file       (expand-file-name "places"    my/state-dir)
      bookmark-default-file (expand-file-name "bookmarks" my/state-dir)
      project-list-file     (expand-file-name "projects"  my/state-dir))

;; --- Regenerable caches -> CACHE --------------------------------------------
(dolist (d (list (expand-file-name "auto-save-list/" my/cache-dir)
                 (expand-file-name "transient/"      my/cache-dir)
                 (expand-file-name "url/"            my/cache-dir)))
  (make-directory d t))
(setq url-configuration-directory (expand-file-name "url/" my/cache-dir)
      transient-levels-file  (expand-file-name "transient/levels.el"  my/cache-dir)
      transient-values-file  (expand-file-name "transient/values.el"  my/cache-dir)
      transient-history-file (expand-file-name "transient/history.el" my/cache-dir))

;; --- Data -------------------------------------------------------------------
(setq nsm-settings-file (expand-file-name "network-security.data" my/data-dir)
      custom-file       (expand-file-name "custom.el" my/state-dir))
(when (file-exists-p custom-file) (load custom-file nil t))

;;; early-init.el ends here
