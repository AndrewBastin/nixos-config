/**
 * emacs-context — muru-local extension (NOT vendored from upstream).
 *
 * Lives in emacs/ alongside muru-note.ts: together they are the whole
 * Emacs-facing surface of muru-stuff, grouped so the plugin root only holds
 * the Emacs-agnostic extensions (unified-edit, agent-bell).
 *
 * When muru runs inside an Emacs session (INSIDE_EMACS set), append the
 * Emacs capability briefing to the system prompt so the agent knows it can
 * drive the host Emacs through its server socket.
 *
 * The briefing is muru's OWN text — it deliberately documents built-in
 * Emacs operations (compose raw emacsclient elisp from the patterns) and
 * does NOT mention the my/agent-* wrapper functions that agent.el keeps for
 * Claude Code. agent.el's functions remain available to any agent that
 * knows about them, but muru is briefed to work without them: the /emacs
 * command (muru-note.ts) additionally gives it a note channel and injects
 * the SPC C bindings into Emacs, but the drive-Emacs capability here is
 * self-contained raw elisp. Keep the two texts independent on purpose.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const EMACS_BRIEFING = `You are running inside the user's Emacs session, in an embedded terminal. You can drive that Emacs through its server socket:
  emacsclient -e '<elisp>'
($EMACS_SOCKET_NAME is preset, so no flags are needed.)

Conventions: pass absolute paths (Emacs's working directory differs from this shell's); keep evals short and non-blocking; never steal the user's focus. There are no wrapper functions — compose the elisp from the built-in patterns below and figure out the rest from there.

Useful built-in Emacs operations:

- Show a file to the user at a LINE without stealing focus (returns the buffer name):
  (let* ((buf (find-file-noselect "/abs/path/to/file"))
         (win (display-buffer buf '((display-buffer-reuse-window
                                     display-buffer-pop-up-window
                                     display-buffer-use-some-window)
                                    (inhibit-same-window . t)))))
    (when win (set-window-point win (with-current-buffer buf
                                      (goto-char (point-min))
                                      (forward-line (1- 42))
                                      (point))))
    (buffer-name buf))

- What the user is looking at right now (evaluate in the current buffer):
  (buffer-file-name)            ; absolute path, or nil for scratch buffers
  (line-number-at-pos)          ; the line the point is on
  (use-region-p)                ; whether a region is active
  (buffer-substring-no-properties (region-beginning) (region-end))  ; selected text
  (buffer-modified-p)           ; unsaved edits in this buffer
  (buffer-list)                 ; all buffers; check each with buffer-modified-p

- Notify the user in the echo area (ONLY when responding to a @muru note):
  (message "[agent] your message here")

- Flymake diagnostics for FILE (open it first with find-file-noselect, give
  the language server a moment; nil when none or flymake is off):
  (with-current-buffer (find-file-noselect "/abs/path/to/file")
    (mapcar (lambda (d)
              (save-excursion
                (goto-char (flymake-diagnostic-beg d))
                (list (line-number-at-pos) (current-column)
                      (flymake-diagnostic-type d) (flymake-diagnostic-text d))))
            (flymake-diagnostics)))

- Save modified buffers:
  (save-some-buffers)`;

export default function (pi: ExtensionAPI) {
	// INSIDE_EMACS is set by Emacs for every subprocess it spawns (M-x shell,
	// eshell, term, ghostel terminals, …). It is fixed for the process
	// lifetime, so check once at load: outside Emacs we register nothing and
	// pay zero per-turn cost.
	if (!process.env.INSIDE_EMACS) return;

	pi.on("before_agent_start", async (event) => {
		return {
			systemPrompt: `${event.systemPrompt}\n\n${EMACS_BRIEFING}`,
		};
	});
}
