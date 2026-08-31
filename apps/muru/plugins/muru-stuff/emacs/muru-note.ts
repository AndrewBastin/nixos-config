/**
 * muru-note — muru-local extension (NOT vendored from upstream).
 *
 * Lives in emacs/ alongside emacs-context.ts: together they are the whole
 * Emacs-facing surface of muru-stuff.
 *
 * /emacs: opt-in Unix-socket bridge from the user's Emacs to ONE muru
 * instance. Run `/emacs` on the Pi instance you want to be the copilot; it
 * opens /tmp/emacs-muru/<pid>/emacs.sock and injects the user-facing glue
 * (my/muru-send + the `SPC C s` binding) into the host Emacs. Standby Pi
 * instances never bind a socket, so only the instance you chose receives
 * notes.
 *
 * Emacs side (injected, not part of the Emacs config): `SPC C s`
 * (my/muru-send) saves the buffer, grabs the active region or the nearest
 * `@muru` comment at/above point, and sends one JSON message over the
 * socket. The Pi side acks so Emacs can fail fast when no instance is
 * listening or when the agent is busy.
 *
 * Notes arrive as ACTION tasks, not questions (questions stay in the Pi
 * TUI): the message carries only the note text and the referenced
 * file:line, and tells the agent to work exactly the stated goal — the
 * note text is the complete spec, no inferred meaning or scope around it —
 * then notify the user of the path it took when done. There is NO queueing:
 * sendUserMessage() delivers immediately when the agent is idle and throws
 * synchronously while it is streaming (pi only queues when passed an explicit
 * deliverAs) — that throw is what surfaces as a "muru is busy" rejection on
 * the Emacs side. Resend when free.
 *
 * While listening, the agent also gets the `ask_user` interview tool: a
 * mid-turn question rendered in the Emacs minibuffer (multiple choice via
 * options, else free text), blocking until the user answers or cancels.
 *
 * Status is AGENT-DECLARED, not inferred. The `set_status` tool takes a 3-5
 * word phrase and shows it in the host Emacs mode line (my/muru-set-status,
 * orange, injected by /emacs — never part of the Emacs config) and in muru's
 * own footer. Working state only: the mode-line segment is empty when idle and
 * cleared on agent_settled, because finishing a note is already announced by
 * the agent's own minibuffer message. muru's footer additionally shows
 * "Listening to Emacs" while idle, since that is bridge state rather than
 * activity.
 *
 * An earlier version derived this from tool_execution_start instead. That can
 * only ever name a mechanical step ("reading muru-note.ts"); the agent knows
 * the intent ("checking why the ack times out"), which is what is worth
 * showing to someone looking at Emacs rather than at the muru pane.
 *
 * Lifecycle: the socket lives only while enabled and is closed on
 * session_shutdown. The on/off state is persisted via pi.appendEntry so a
 * /reload in the same session keeps listening; a fresh session does not.
 */
import * as fs from "node:fs";
import * as net from "node:net";
import * as path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const execFileP = promisify(execFile);

const SOCKET_ROOT = "/tmp/emacs-muru";
const STATUS_KEY = "muru";
const LISTENING_TEXT = "Listening to Emacs";
const MAX_NOTE_LENGTH = 8000;
const MAX_STATUS_WORDS = 5;
const ACK_TIMEOUT_MS = 8000;

let server: net.Server | null = null;
let listening = false;
// Whether the bridge was EVER started this session. session_shutdown uses
// this to skip stopServer entirely when /emacs was never turned on, so a
// bridge-less muru instance doesn't fire a pointless emacsclient clear at
// exit (which, even wrapped in ignore-errors, is one spawn per exit).
let everListened = false;

const pidDir = () => path.join(SOCKET_ROOT, String(process.pid));
const sockPath = () => path.join(pidDir(), "emacs.sock");
const elispPath = () => path.join(pidDir(), "muru.el");

// ---------------------------------------------------------------------------
// The Elisp injected into the user's Emacs by /emacs. Kept as a template
// string here so the whole Emacs-side surface of this feature is a property
// of the Pi extension, not of the Emacs config. The socket path is baked in
// at injection time so my/muru-send always talks to THIS instance.
//
// Mind the escaping: this is a JS template literal, so every backslash the
// elisp needs is doubled here and every backtick in a docstring must be
// escaped. A miscount is invisible in review and only fails in the user's
// Emacs. Byte-compile the generated file after editing:
//   emacs -Q --batch -f batch-byte-compile /tmp/emacs-muru/<pid>/muru.el
// Warnings there are real bugs (that is how the `rend` void-variable on the
// region path was caught); treat a clean compile as the bar for a change.
// ---------------------------------------------------------------------------
function injectedElisp(): string {
	const sock = JSON.stringify(sockPath());
	return `;;; muru.el --- injected by the muru /emacs command.  -*- lexical-binding: t; -*-
;; Sends @muru notes from this buffer to the muru instance listening on the
;; socket below. Regenerated and re-eval'd on every /emacs, so the socket
;; path stays fresh across Pi restarts. Additive: /emacs off only closes the
;; socket; these bindings remain but fail fast ("No Pi listening").

(require 'json)

(defvar my/muru-socket ${sock}
  "Unix socket of the muru instance that injected this file.")

(defun my/muru--find-note ()
  "Find the nearest @muru comment at/above point.
Returns (TEXT . LINE), or nil when there is none."
  (save-excursion
    (goto-char (line-beginning-position))
    (let (done note)
      (while (not done)
        ;; Check the CURRENT line first, then walk upward — the while
        ;; condition must never run before the first line is inspected
        ;; (bobp is already true at line 1, so a pre-checked loop skips it).
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (if (string-match "@muru\\\\(.*\\\\)" line)
              (setq note (cons (string-trim
                                (replace-regexp-in-string
                                 "\\\\*/\\\\s-*\\\\'" "" (match-string 1 line)))
                               (line-number-at-pos))
                    done t)
            (if (bobp)
                (setq done t)
              (forward-line -1)))))
      note)))

(defun my/muru--send-json (payload)
  "Send PAYLOAD (alist) to the muru socket and report the ack."
  (let ((proc (condition-case nil
                  (make-network-process
                   :name "muru" :family 'local :service my/muru-socket
                   :noquery t)
                (error nil))))
    (unless proc
      (user-error "No Pi listening — run /emacs on the target Pi"))
    (unwind-protect
        (let ((acc "") (deadline (+ (float-time) ${ACK_TIMEOUT_MS / 1000})) (done nil))
          (set-process-filter
           proc (lambda (_p s) (setq acc (concat acc s))))
          (process-send-string proc (concat (json-encode payload) "\\n"))
          ;; Poll in short slices: under some builds/terminals the local
          ;; socket connect can lag, so the loop must survive early empty
          ;; polls until the deadline instead of giving up after one.
          (while (and (not done) (< (float-time) deadline))
            (accept-process-output proc 0.25)
            (when (string-match "\\n" acc) (setq done t)))
          (if done
              (let ((resp (condition-case nil
                              (json-read-from-string
                               (substring acc 0 (match-beginning 0)))
                            (error nil))))
                (if resp
                    (if (eq (cdr (assq 'ok resp)) t)
                        ;; json-read-from-string uses json-key-type, which
                        ;; defaults to 'symbol — keys arrive as symbols, so
                        ;; match with assq, never assoc. JSON "false" also
                        ;; arrives as the :json-false symbol, so test equality
                        ;; against t, not truthiness.
                        (message "muru: delivered (pid %s)" (or (cdr (assq 'pid resp)) "?"))
                      (message "muru: %s" (or (cdr (assq 'error resp)) "rejected")))
                  (message "muru: unreadable reply %s" (substring acc 0 (min (length acc) 200)))))
            (message "muru: no reply from %s" my/muru-socket)))
      (delete-process proc))))

(defun my/muru-send ()
  "Send the @muru note (active region, else nearest @muru comment) to the
connected muru instance. Fails with a message when muru is busy or not
listening — there is no queueing; resend when it is free."
  (interactive)
  (let* ((file (buffer-file-name))
         (region (use-region-p))
         (rbeg (and region (region-beginning)))
         (rend (and region (region-end)))
         (note (and (not region) (my/muru--find-note)))
         (text (cond (region (buffer-substring-no-properties rbeg rend))
                     (note (car note))
                     (t (if (called-interactively-p 'any)
                            (read-string "muru: ")
                          ;; Never block: a non-interactive eval (emacsclient,
                          ;; muru driving Emacs) must fail loudly instead of
                          ;; wedging the Emacs eval thread on a minibuffer read.
                          (user-error "No @muru note or region to send")))))
         (line (cond (region (line-number-at-pos rbeg))
                     (note (cdr note))
                     (t (line-number-at-pos)))))
    (when (buffer-modified-p) (save-buffer))
    (let ((payload (list (cons "text" text) (cons "line" line))))
      (when file (setq payload (nconc payload (list (cons "file" file)))))
      (my/muru--send-json payload))))

(defconst my/muru-ask-escape "Something else (type my own answer)"
  "Entry appended to every multiple-choice prompt.")

(defun my/muru-ask (question &optional options)
  "Ask QUESTION in the minibuffer; return the answer string.
With OPTIONS, offer them as completion candidates plus an escape entry,
so the user is never trapped in a list that does not cover their answer:
picking the escape falls through to a free-text prompt. Without OPTIONS,
read free text. Signals a quit when the user presses C-g, which the Pi
side reports back to the agent as a cancellation."
  (if options
      (let ((choice (completing-read question
                                     (append options (list my/muru-ask-escape))
                                     nil t)))
        (if (equal choice my/muru-ask-escape)
            (read-string (concat question " "))
          choice))
    (read-string (concat question " "))))

(defvar my/muru-status nil
  "What muru is doing right now (<=4 words), or nil when it is not working.")
(put 'my/muru-status 'risky-local-variable t)

(defvar my/muru--mode-line-entry '(:eval (my/muru--mode-line))
  "The construct spliced into \`mode-line-format'.")

(defface my/muru-status-face
  '((t :foreground "#FFA066"))   ; Kanagawa surimiOrange, as used in modeline.el
  "Face for the muru activity segment in the mode line.")

(defun my/muru--mode-line ()
  "Render the muru segment: empty unless muru is mid-turn."
  (if my/muru-status
      (concat "  " (propertize (concat "[muru: " my/muru-status "]")
                               'face 'my/muru-status-face))
    ""))

(defun my/muru--splice (fmt)
  "Return FMT with the muru segment before the right-align marker.
Appends at the end when there is no marker. Recursive so this needs
neither cl-lib nor seq."
  (cond ((null fmt) (list my/muru--mode-line-entry))
        ((eq (car fmt) 'mode-line-format-right-align)
         (cons my/muru--mode-line-entry fmt))
        (t (cons (car fmt) (my/muru--splice (cdr fmt))))))

(defun my/muru--install-local ()
  "Splice the segment into THIS buffer's mode line, if it has its own.
Skips buffers whose mode line is nil — that is a deliberately hidden
mode line, and splicing into nil would resurrect it."
  (when (and (local-variable-p 'mode-line-format)
             mode-line-format
             (listp mode-line-format)
             (not (member my/muru--mode-line-entry mode-line-format)))
    (setq mode-line-format (my/muru--splice mode-line-format))))

(defun my/muru--install-mode-line ()
  "Put the muru segment in every mode line, default and buffer-local.
\`mode-line-format' is a per-buffer variable: any buffer that already has
a local value keeps it, so setq-default alone reaches only the buffers
that never got one — which is why the segment showed up in the default
value while every visible window stayed unchanged. Hence the sweep over
live buffers plus a hook for ones created later.

Additive and idempotent, but NOT permanent: re-evaluating the Emacs
config replaces \`mode-line-format' wholesale and drops the segment. The
next /emacs, or the next status push, puts it back."
  (let ((fmt (default-value 'mode-line-format)))
    (when (and fmt (listp fmt) (not (member my/muru--mode-line-entry fmt)))
      (setq-default mode-line-format (my/muru--splice fmt))))
  (dolist (buf (buffer-list))
    (with-current-buffer buf (my/muru--install-local)))
  (add-hook 'after-change-major-mode-hook #'my/muru--install-local))

(defun my/muru-set-status (text)
  "Show TEXT in the mode line while muru works; empty TEXT clears it.
Called by the Pi side on every tool call — deliberately the only thing
muru pushes into Emacs unprompted. Idle and completion are NOT reported
here: finishing a note is announced by the agent's own minibuffer
message, so a persistent listening segment would be pure noise."
  (my/muru--install-mode-line)
  (setq my/muru-status
        (and (stringp text) (not (string-empty-p text)) text))
  (force-mode-line-update t))

(when (fboundp 'evil-define-key)
  (evil-define-key '(normal visual) 'global
    (kbd "<leader>C s") #'my/muru-send))
`;
}

// ---------------------------------------------------------------------------
// Note → user message: action framing + file:line + bounded code snippet.
// ---------------------------------------------------------------------------
export type NotePayload = {
	text?: string;
	file?: string;
	line?: number;
};

/**
 * Build the full user message for an incoming note: the action framing, the
 * note text (trimmed and bounded to MAX_NOTE_LENGTH), the referenced
 * file:line, and the standing "work the stated goal exactly" instruction tail.
 */
export function buildNoteMessage(p: NotePayload): string {
	const text = (p.text ?? "").trim().slice(0, MAX_NOTE_LENGTH);
	let msg = `@muru note from Emacs (an action to do, not a question):\n\n${text}`;
	if (p.file) {
		const loc = path.resolve(p.file);
		msg += `\n\nReference: ${loc}${p.line ? `:${p.line}` : ""}`;
	}
	msg +=
		"\n\nWork the stated goal exactly, nothing more: the note text above is the complete spec — infer " +
		"no additional meaning, scope, or adjacent tasks around it, and touch nothing the goal does not " +
		"require. Call set_status with a 3-5 word phrase as you start, and again whenever you move on to a " +
		"visibly different piece of work — the user is looking at Emacs, not at this pane, so it is the only " +
		"sign of life they get. When done, notify the user in Emacs in a few lines: what you changed and " +
		"where (file:line). When the note was sent from an @muru comment at the Reference, delete that " +
		"comment once the work is done, so a later send at that spot does not re-fire the same note.";
	return msg;
}

/**
 * Derive a short (≤4 words) human-readable summary of a tool call, used for
 * the "what the agent is doing" line in muru's footer and the Emacs mode line.
 * Returns undefined when nothing sensible can be said.
 */

// ---------------------------------------------------------------------------
// Socket server lifecycle.
// ---------------------------------------------------------------------------
/**
 * ask_user — interview tool: the agent asks the user a question through the
 * host Emacs minibuffer mid-turn. Options become a completing-read, always
 * with an escape entry appended so a list that does not cover the real answer
 * cannot trap the user; without options it is a free-text read-string. The
 * tool blocks the turn until the user answers or cancels (C-g), which is the
 * point of an interview.
 *
 * Blocking is mutual: while the minibuffer is open Emacs is wedged on it, so
 * muru cannot drive Emacs until the user answers. That is acceptable for a
 * question the user asked to be asked, but it is why this must stay rare.
 */
export async function askUserViaEmacs(
	question: string,
	options: string[] | undefined,
	signal?: AbortSignal,
): Promise<string> {
	const q = JSON.stringify(question);
	// The prompting logic lives in my/muru-ask (injected elisp), not in a form
	// composed here: the escape entry that keeps the user out of a dead-end
	// option list has to be guaranteed in ONE place, and that place is the side
	// that actually draws the minibuffer.
	const form =
		options && options.length > 0
			? `(my/muru-ask ${q} (list ${options.map((o) => JSON.stringify(o)).join(" ")}))`
			: `(my/muru-ask ${q})`;
	const { stdout } = await execFileP("emacsclient", ["-e", form], { signal });
	let out = stdout.trim();
	// emacsclient prints Lisp string values quoted; unquote simple strings.
	if (out.startsWith('"') && out.endsWith('"')) {
		try {
			out = JSON.parse(out) as string;
		} catch {
			/* keep raw */
		}
	}
	return out;
}

// ---------------------------------------------------------------------------
// Mirror the activity summary into the Emacs mode line (my/muru-set-status,
// injected by /emacs — see muru-elisp.ts). Fire-and-forget: the agent must
// never block on the user's Emacs.
//
// Coalesced, not queued: at most one emacsclient in flight, and while it runs
// only the NEWEST pending activity is kept. A slow or wedged Emacs therefore
// costs one stale frame, never a backlog of spawns trailing behind the agent.
// ---------------------------------------------------------------------------
let statusInFlight = false;
let pendingStatus: string | null = null;

function pushEmacsStatus(text: string): void {
	pendingStatus = text;
	if (statusInFlight) return;
	statusInFlight = true;
	void (async () => {
		try {
			while (pendingStatus !== null) {
				const next = pendingStatus;
				pendingStatus = null;
				try {
					await execFileP("emacsclient", [
						"-e",
						// ignore-errors, not just the catch below: a void
						// my/muru-set-status (elisp never injected, or wiped by
						// an Emacs restart) fails SILENTLY on the emacsclient side
						// but still logs "Symbol's function definition is void"
						// into the host Emacs's *Messages* every single call.
						`(ignore-errors (my/muru-set-status ${JSON.stringify(next)}))`,
					]);
				} catch {
					/* Emacs gone, or the bridge elisp never loaded — a status
					   line is not worth a retry, let alone a user-facing error. */
				}
			}
		} finally {
			statusInFlight = false;
		}
	})();
}

async function injectElisp(): Promise<void> {
	const file = elispPath();
	await fs.promises.writeFile(file, injectedElisp());
	try {
		const { stdout, stderr } = await execFileP(
			"emacsclient",
			["-e", `(load-file ${JSON.stringify(file)})`],
		);
		const out = (stdout + stderr).trim();
		if (out && !/^t$/i.test(out)) console.warn(`[muru-note] elisp injection: ${out}`);
	} catch (err) {
		console.warn("[muru-note] elisp injection failed:", err);
	}
}

/**
 * Start the Emacs bridge: create the private 0700 dir under /tmp/emacs-muru,
 * listen on emacs.sock (unlinking any stale socket from a dead instance
 * first), and inject the elisp glue into the host Emacs. Incoming note
 * messages are handled inline as they arrive.
 */
export async function startServer(pi: ExtensionAPI): Promise<void> {
	// 0700, not the ambient umask: /tmp is world-writable and muru.el below
	// is load-file'd into the user's Emacs. Nobody else gets to write here.
	await fs.promises.mkdir(pidDir(), { recursive: true, mode: 0o700 });
	try {
		await fs.promises.unlink(sockPath()); // stale socket from a dead instance
	} catch {
		/* not there — fine */
	}
	server = net.createServer((sock) => {
		let buf = "";
		sock.on("data", (chunk) => {
			buf += chunk.toString("utf-8");
			if (buf.length > 1_000_000) {
				sock.end(JSON.stringify({ ok: false, error: "note too large" }) + "\n");
				sock.destroy();
				return;
			}
			const nl = buf.indexOf("\n");
			if (nl < 0) return;
			const raw = buf.slice(0, nl);
			buf = buf.slice(nl + 1);
			sock.end(JSON.stringify(handleNote(pi, raw)) + "\n");
		});
		sock.on("error", () => {});
	});
	await new Promise<void>((resolve, reject) => {
		server!.once("error", reject);
		server!.listen(sockPath(), () => {
			server!.removeListener("error", reject);
			resolve();
		});
	});
	await injectElisp();
}

function handleNote(
	pi: ExtensionAPI,
	raw: string,
): { ok: boolean; pid?: number; error?: string } {
	let p: NotePayload;
	try {
		p = JSON.parse(raw) as NotePayload;
	} catch {
		return { ok: false, error: "malformed JSON" };
	}
	if (typeof p.text !== "string" || !p.text.trim()) {
		return { ok: false, error: "empty note" };
	}
	const message = buildNoteMessage(p);
	// No queueing: sendUserMessage throws while the agent is streaming, which
	// is exactly the "busy" signal we surface back to Emacs. Resend when free.
	try {
		pi.sendUserMessage(message);
	} catch (err) {
		console.warn("[muru-note] note rejected while busy:", err);
		return { ok: false, error: "muru is busy — try again when it finishes" };
	}
	return { ok: true, pid: process.pid };
}

/**
 * Tear the bridge down: clear the Emacs mode-line segment (awaited, unlike
 * the fire-and-forget status pushes — on session_shutdown a dropped call
 * would leave a stale "[muru: …]" in the user's mode line), close the server,
 * and remove the socket, the generated elisp, and the private dir.
 */
export async function stopServer(): Promise<void> {
	// Awaited, unlike pushEmacsStatus: on session_shutdown a fire-and-forget
	// call loses the race with process exit and leaves a stale "[muru: …]"
	// segment in the user's mode line until the next /emacs.
	try {
		// ignore-errors: muru.el is only defined after /emacs injected it, and
		// emacsclient evals that hit a void function fail exit-0 on the client
		// side while logging the void-function error in *Messages* — the catch
		// here can never see it, so guard it at the source instead.
		await execFileP("emacsclient", ["-e", '(ignore-errors (my/muru-set-status ""))']);
	} catch {
		/* Emacs gone or bridge never injected — nothing to clear. */
	}
	if (server) {
		const s = server;
		server = null;
		await new Promise<void>((r) => s.close(() => r()));
	}
	for (const f of [sockPath(), elispPath()]) {
		try {
			await fs.promises.unlink(f);
		} catch {
			/* already gone */
		}
	}
	try {
		await fs.promises.rmdir(pidDir());
	} catch {
		/* gone — fine */
	}
}

/**
 * Extension entry point. Registers nothing when not running inside Emacs
 * (INSIDE_EMACS is fixed for the process lifetime). Inside Emacs it registers
 * the /emacs toggle command, the session lifecycle listeners that restore and
 * stop the bridge, the status mirroring hooks, and the ask_user interview tool.
 */
export default function (pi: ExtensionAPI) {
	// Same load-time gate as emacs-context.ts: INSIDE_EMACS is fixed for the
	// process lifetime, so outside Emacs we register nothing — no /emacs
	// command, and no ask_user schema spending tokens in every non-Emacs
	// session just to answer "the bridge is off".
	if (!process.env.INSIDE_EMACS) return;

	const restoreListening = async (ctx: ExtensionContext) => {
		let wasListening = false;
		for (const entry of ctx.sessionManager.getEntries()) {
			if (
				entry.type === "custom" &&
				entry.customType === "muru-note" &&
				typeof (entry.data as { listening?: boolean } | undefined)?.listening === "boolean"
			) {
				wasListening = (entry.data as { listening: boolean }).listening;
			}
		}
		if (wasListening) {
			try {
				await startServer(pi);
				listening = true;
				everListened = true;
				ctx.ui.setStatus(STATUS_KEY, LISTENING_TEXT);
			} catch (err) {
				console.warn("[muru-note] failed to restore the Emacs bridge:", err);
			}
		}
	};

	pi.on("session_start", async (_event, ctx) => {
		await restoreListening(ctx);
	});

	pi.on("session_shutdown", async () => {
		listening = false;
		// Skip entirely when the bridge never started this session: the clear
		// only matters if we put a segment in the user's mode line, and a
		// never-started bridge has a null server and nothing to clean up.
		if (everListened) await stopServer();
	});

	pi.registerCommand("emacs", {
		description:
			"Toggle the Emacs @muru bridge: SPC C s sends a note to this Pi instance",
		handler: async (_args, ctx) => {
			if (listening) {
				await stopServer();
				listening = false;
				ctx.ui.setStatus(STATUS_KEY, undefined);
				pi.appendEntry("muru-note", { listening: false });
				ctx.ui.notify("Emacs bridge disabled", "info");
			} else {
				try {
					await startServer(pi);
				} catch (err) {
					ctx.ui.notify(`Could not start the Emacs bridge: ${String(err)}`, "error");
					return;
				}
				listening = true;
				everListened = true;
				pi.appendEntry("muru-note", { listening: true });
				ctx.ui.setStatus(STATUS_KEY, LISTENING_TEXT);
			}
		},
	});

	// A turn ending means whatever the agent last announced is stale. Clear
	// both sinks rather than leaving the last activity frozen on screen.
	pi.on("agent_settled", (_event, ctx) => {
		if (!listening) return;
		ctx.ui.setStatus(STATUS_KEY, LISTENING_TEXT);
		pushEmacsStatus("");
	});

	// Activity indicator: the agent SAYS what it is doing, rather than us
	// guessing from tool events. Tool-derived text could only ever describe one
	// mechanical step ("reading foo.ts"); the agent knows the actual intent
	// ("tracking down the socket leak"), which is the useful thing to show
	// someone who is looking at Emacs and not at the muru pane.
	pi.registerTool({
		name: "set_status",
		label: "Set Status",
		description:
			"Show the user what you are working on right now, in their Emacs mode line. " +
			"Pass a 3-5 word present-tense phrase describing the CURRENT piece of work, e.g. " +
			'"tracking down the socket leak" or "rewriting the note parser". ' +
			"Call this when you START a distinct chunk of work and again whenever the work " +
			"changes to something a person would describe differently — not for every tool " +
			"call, and not for trivial steps. Describe intent, not mechanics: prefer " +
			'"checking why the ack times out" over "reading muru-note.ts". ' +
			"The indicator clears by itself when your turn ends, so there is no need to " +
			"unset it. Requires the Emacs bridge (/emacs).",
		parameters: Type.Object({
			activity: Type.String({
				description: "3-5 word present-tense phrase, e.g. \"wiring up the status tool\".",
			}),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const { activity } = params as { activity: string };
			// Trimmed to MAX_STATUS_WORDS: the mode line is shared with the rest of
			// the user's segments, and a model that ignores the 3-5 word rule must
			// not be able to push the line into wrapping.
			const text = activity.trim().split(/\s+/).filter(Boolean).slice(0, MAX_STATUS_WORDS).join(" ");
			if (!text) {
				return {
					content: [{ type: "text", text: "Nothing set: activity was empty." }],
					details: {},
				};
			}
			if (!listening) {
				return {
					content: [
						{
							type: "text",
							text: "The Emacs bridge is off (run /emacs first), so there is nowhere to show this. Carry on without it.",
						},
					],
					details: {},
				};
			}
			ctx.ui.setStatus(STATUS_KEY, text);
			pushEmacsStatus(text);
			return { content: [{ type: "text", text: `Status: ${text}` }], details: {} };
		},
	});

	// Interview tool: agent asks the user a question in the Emacs minibuffer
	// during a turn. Only usable while the bridge is on; when off it tells the
	// agent to ask in the terminal instead.
	pi.registerTool({
		name: "ask_user",
		label: "Ask User",
		description:
			"Ask the user a question in the Emacs minibuffer and wait for the answer (requires the " +
			"Emacs bridge, /emacs). Use it whenever a decision is genuinely the user's to make and " +
			"guessing wrong would waste real work — not for things you can determine yourself. " +
			"Pass options for a multiple-choice pick, or omit them for a free-text answer; prefer " +
			"options whenever you can name the plausible answers, since picking is faster than typing. " +
			"An escape entry is ALWAYS appended for the user to type their own answer, so your options " +
			"never have to be exhaustive and you should not add an 'other' entry yourself. Blocks your " +
			"turn until the user answers or cancels with C-g.",
		parameters: Type.Object({
			question: Type.String({
				description:
					"The question, as one clear sentence ending in '?'. It is shown as a minibuffer prompt, " +
					"so keep it short enough to read on one line.",
			}),
			options: Type.Optional(
				Type.Array(
					Type.String({
						description:
							"A choice, phrased as the answer itself ('use a Unix socket'), not as a label ('option A'). " +
							"Omit the whole array for a free-text question.",
					}),
				),
			),
		}),
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			const { question, options } = params as { question: string; options?: string[] };
			if (!listening) {
				return {
					content: [
						{
							type: "text",
							text: "The Emacs bridge is off (run /emacs first). Ask the user directly in the terminal instead.",
						},
					],
					details: {},
				};
			}
			try {
				const answer = await askUserViaEmacs(question, options, signal);
				return {
					content: [{ type: "text", text: `User's answer: ${answer}` }],
					details: {},
				};
			} catch (err) {
				return {
					content: [
						{
							type: "text",
							text: `The question was cancelled or Emacs was unreachable (${String(err).slice(0, 300)}). ` +
								"Proceed with your best judgment, or ask again.",
						},
					],
					details: {},
				};
			}
		},
	});
}
