/**
 * agent-bell — muru-local extension (NOT vendored from upstream).
 *
 * Rings the terminal bell (BEL, \x07) when the agent finishes and is awaiting
 * the user's next input. Hooks agent_settled rather than agent_end so the bell
 * only fires once pi is truly idle — no retry, auto-compaction retry, or
 * queued follow-up left to run (agent_end can fire while pi is still going to
 * continue automatically).
 *
 * BEL is a control character the terminal emulator handles itself (audible
 * bell and/or visual flash); it never renders as text, so writing it straight
 * to stdout is safe even while the TUI is mid-draw.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.on("agent_settled", async (_event, ctx) => {
		// Only the interactive TUI has a human waiting on the other end; in
		// print mode stdout is the answer, not a terminal to ring, and in RPC
		// mode stdout carries the protocol stream.
		if (ctx.mode !== "tui") return;
		process.stdout.write("\x07");
	});
}
