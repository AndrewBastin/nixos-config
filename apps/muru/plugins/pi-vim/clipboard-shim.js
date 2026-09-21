// A @mariozechner/clipboard-compatible shim (setText/hasText/getText) that
// drives the platform clipboard tools pi itself uses, in the same order:
// Termux helpers, wl-copy/wl-paste, xclip, xsel, pbcopy/pbpaste.
//
// pi-vim runs this inside the child helper it spawns for every clipboard
// operation; see ./default.nix for why that child is node and why this exists.
// Writes use stdio ["pipe", "ignore", "ignore"] so a tool that forks a
// background selection server (wl-copy) does not keep spawnSync waiting on an
// inherited stdout/stderr pipe.
"use strict";

const { spawnSync } = require("node:child_process");

const TIMEOUT_MS = 5000;

function read(command, args) {
  try {
    const result = spawnSync(command, args, {
      encoding: "utf8",
      timeout: TIMEOUT_MS,
      stdio: ["ignore", "pipe", "ignore"],
      windowsHide: true,
    });
    if (result.error || result.status !== 0) return null;
    return result.stdout ?? "";
  } catch {
    return null;
  }
}

function write(command, args, text) {
  try {
    const result = spawnSync(command, args, {
      input: text,
      encoding: "utf8",
      timeout: TIMEOUT_MS,
      stdio: ["pipe", "ignore", "ignore"],
      windowsHide: true,
    });
    return !result.error && result.status === 0;
  } catch {
    return false;
  }
}

function writeCandidates(env) {
  const candidates = [];
  if (env.TERMUX_VERSION) candidates.push(["termux-clipboard-set", []]);
  if (process.platform === "darwin") candidates.push(["pbcopy", []]);
  else if (process.platform === "win32") candidates.push(["clip", []]);
  if (env.WAYLAND_DISPLAY) candidates.push(["wl-copy", []]);
  if (env.DISPLAY) {
    candidates.push(
      ["xclip", ["-selection", "clipboard"]],
      ["xsel", ["--clipboard", "--input"]],
    );
  }
  return candidates;
}

function readCandidates(env) {
  const candidates = [];
  if (env.TERMUX_VERSION) candidates.push(["termux-clipboard-get", []]);
  if (process.platform === "darwin") candidates.push(["pbpaste", []]);
  if (env.WAYLAND_DISPLAY) {
    candidates.push(["wl-paste", ["--no-newline", "--type", "text"]]);
  }
  if (env.DISPLAY) {
    candidates.push(
      ["xclip", ["-selection", "clipboard", "-out"]],
      ["xsel", ["--clipboard", "--output"]],
    );
  }
  return candidates;
}

function copyToClipboard(text) {
  for (const [command, args] of writeCandidates(process.env)) {
    if (write(command, args, text)) return;
  }
  throw new Error("clipboard write unavailable");
}

// hasText() and getText() are called back to back in the same child, so cache
// the read rather than shelling out twice.
let cached;
function getText() {
  if (cached !== undefined) return cached;
  for (const [command, args] of readCandidates(process.env)) {
    const output = read(command, args);
    if (output !== null) {
      cached = output;
      return output;
    }
  }
  cached = null;
  return null;
}

async function hasText() {
  return getText() !== null;
}

module.exports = {
  setText: copyToClipboard,
  copyToClipboard,
  hasText,
  getText,
};
