/**
 * emacs-context — muru-local extension (NOT vendored from upstream).
 *
 * When muru runs inside an Emacs session (INSIDE_EMACS set), append the Emacs
 * capability briefing to the system prompt so the agent knows it can drive the
 * host Emacs through its server socket.
 *
 * The briefing text is copied verbatim from the Ghostel integration in
 * apps/emacs/emacs.d/lisp/agent.el (`my/agent-briefing`), which injects the
 * same text into Claude Code via a `--append-system-prompt` zsh wrapper baked
 * into the ghostel shell shim. We deliberately do NOT copy that application
 * style (shell shim + CLI flag); this is pi's native equivalent: the
 * `before_agent_start` event chains the system prompt per turn. If agent.el's
 * briefing or entry-point docstrings change, re-sync EMACS_BRIEFING below.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const EMACS_BRIEFING = `You are running inside the user's Emacs session, in an embedded terminal. You can drive that Emacs through its server socket:
  emacsclient -e '<elisp>'
($EMACS_SOCKET_NAME is preset, so no flags are needed.)

The entry points below are elisp functions — invoke them via emacsclient, e.g.
  emacsclient -e '(my/agent-open "/abs/path/to/file")'
Results return as elisp data. Conventions: pass absolute paths (Emacs's working directory differs from this shell's); keep evals short and non-blocking; never steal the user's focus.

Preferred entry points:

- (my/agent-open FILE &optional LINE): show FILE to the user, at LINE.
Displays FILE in another Emacs window WITHOUT stealing the user’s focus.
FILE should be an absolute path.  Returns the buffer name shown.
- (my/agent-diagnostics FILE): language diagnostics for FILE.
Returns a list of (LINE COL SEVERITY MESSAGE) rows from flymake/eglot, or a
string explaining why none are available (file not open in Emacs — use
my/agent-open first and give the language server a moment — or flymake off).
- (my/agent-context): what the user is looking at right now.
Returns a plist: :file (absolute path or nil), :buffer, :line, :region (text
of the active region, or nil) and :modified (files with unsaved edits).
- (my/agent-notify MSG): notify the user (echo area + window urgency).
Use sparingly — when a long task finishes or you are blocked on the user.

Other elisp is allowed when needed; prefer the entry points above.`;

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
