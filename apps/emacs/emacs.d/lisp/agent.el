;;; agent.el --- Emacs-side API for AI coding agents  -*- lexical-binding: t; -*-

;; AI agents (Claude Code, …) run inside ghostel terminals with
;; $EMACS_SOCKET_NAME exported (ghostel.el §5), so `emacsclient -e' reaches
;; THIS Emacs with no flags.  This file is the curated surface they are
;; briefed to use: each command's docstring doubles as its agent-facing
;; documentation (assembled by `my/agent-briefing'), so the first line states
;; the call shape and the docs can never drift from the code.  Curation is
;; for reliability, not enforcement — an agent with shell access could eval
;; anything anyway; these entry points are the stable, polite ones.

(require 'flymake)

(defun my/agent-open (file &optional line)
  "(my/agent-open FILE &optional LINE): show FILE to the user, at LINE.
Displays FILE in another Emacs window WITHOUT stealing the user's focus.
FILE should be an absolute path.  Returns the buffer name shown."
  (let* ((buf (find-file-noselect (expand-file-name file)))
         (win (display-buffer buf '((display-buffer-reuse-window
                                     display-buffer-pop-up-window
                                     display-buffer-use-some-window)
                                    (inhibit-same-window . t)))))
    (when (and win line)
      (set-window-point win (with-current-buffer buf
                              (save-excursion
                                (goto-char (point-min))
                                (forward-line (1- line))
                                (point)))))
    (buffer-name buf)))

(defun my/agent-diagnostics (file)
  "(my/agent-diagnostics FILE): language diagnostics for FILE.
Returns a list of (LINE COL SEVERITY MESSAGE) rows from flymake/eglot, or a
string explaining why none are available (file not open in Emacs — use
my/agent-open first and give the language server a moment — or flymake off)."
  (let ((buf (get-file-buffer (expand-file-name file))))
    (cond
     ((not buf)
      "file not open in Emacs; (my/agent-open FILE) it first, then retry")
     ((not (buffer-local-value 'flymake-mode buf))
      "flymake is not active in that buffer, so no diagnostics exist")
     (t (with-current-buffer buf
          (mapcar (lambda (d)
                    (save-excursion
                      (goto-char (flymake-diagnostic-beg d))
                      (list (line-number-at-pos)
                            (current-column)
                            (flymake-diagnostic-type d)
                            (flymake-diagnostic-text d))))
                  (flymake-diagnostics)))))))

(defun my/agent-context ()
  "(my/agent-context): what the user is looking at right now.
Returns a plist: :file (absolute path or nil), :buffer, :line, :region (text
of the active region, or nil) and :modified (files with unsaved edits)."
  (let* ((win (frame-selected-window))
         (buf (window-buffer win)))
    (with-current-buffer buf
      (list :file (buffer-file-name)
            :buffer (buffer-name)
            :line (line-number-at-pos (window-point win))
            :region (when (use-region-p)
                      (buffer-substring-no-properties
                       (region-beginning) (region-end)))
            :modified (delq nil
                            (mapcar (lambda (b)
                                      (and (buffer-file-name b)
                                           (buffer-modified-p b)
                                           (buffer-file-name b)))
                                    (buffer-list)))))))

(defun my/agent-notify (msg)
  "(my/agent-notify MSG): notify the user (echo area + window urgency).
Use sparingly — when a long task finishes or you are blocked on the user."
  (message "[agent] %s" msg)
  (when (fboundp 'my/frame-set-urgency)
    (my/frame-set-urgency))
  t)

(defvar my/agent-commands
  '(my/agent-open my/agent-diagnostics my/agent-context my/agent-notify)
  "Agent-facing entry points, in briefing order.
Each symbol's docstring is included verbatim in `my/agent-briefing', so
adding a command here is all it takes to document it to agents.")

(defun my/agent-briefing ()
  "Capability briefing for AI agents, assembled from `my/agent-commands'.
Injected into agent CLIs by the ghostel shell shim via `my/agent-shim-snippet'."
  (concat
   "You are running inside the user's Emacs session, in an embedded terminal. "
   "You can drive that Emacs through its server socket:\n"
   "  emacsclient -e '<elisp>'\n"
   "($EMACS_SOCKET_NAME is preset, so no flags are needed.) Conventions: pass "
   "absolute paths (Emacs's working directory differs from this shell's); "
   "results print as elisp data; keep evals short and non-blocking; never "
   "steal the user's focus. Preferred entry points:\n\n"
   (mapconcat (lambda (fn) (concat "- " (documentation fn) "\n"))
              my/agent-commands "")
   "\nOther elisp is allowed when needed; prefer the entry points above."))

(defun my/agent-shim-snippet ()
  "Zsh snippet defining a `claude' wrapper that injects the Emacs briefing.
Spliced into the generated ghostel shim (ghostel.el §5).  The clod/migu
aliases expand to the word `claude', which zsh resolves through this
function; `command claude' prevents recursion.  Agents launched outside
ghostel never see this shim, so the wrapper cannot leak."
  (concat
   "claude() {\n"
   "  command claude --append-system-prompt "
   (shell-quote-argument (my/agent-briefing))
   " \"$@\"\n"
   "}\n"))

;;; agent.el ends here
