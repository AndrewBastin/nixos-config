# pi-vim — Vim keybindings extension for pi, patched for muru.
#
# pi-vim's clipboard helper resolves @earendil-works/pi-coding-agent from the real
# filesystem at import time, but llm-agents ships pi as a compiled bun binary with
# no dist/, so it exists only inside the binary and the resolve throws — taking the
# whole extension down with it. Point it at the clipboard package pi does ship
# unpacked, and adapt the generated helper to that module's API.
#
# Returns the entry point to pass to pi's -e flag.
{
  lib,
  runCommand,
  callPackage,
  pi,
}:

let
  pi-vim = callPackage ../../../../packages/pi-vim/package.nix {};

  # The last pi-vim version whose clipboard-mirror.ts was actually read against
  # the --replace-fail needles below.
  #
  # `just bump` is free to move pi-vim's version; it is not free to decide the
  # patch still applies. When the two disagree the BUILD fails until a human reads
  # the new source and ratifies it by editing ./last-reviewed. --replace-fail
  # catches a needle that stopped matching; it cannot catch one that still matches
  # while the code around it changed meaning, which is what this guards.
  #
  # It lives in a sibling file, not in this one, because nix-update rewrites the
  # version by textual substitution over the whole package file — an in-file marker
  # holding the same string gets bumped along with it, silently ratifying the very
  # update it exists to stop (verified: 0.13.0 -> 0.14.1 rewrote both lines).
  # nix-update only ever touches package.nix, so ./last-reviewed survives.
  lastReviewed = lib.strings.trim (builtins.readFile ./last-reviewed);

  # pi-vim's clipboard helper resolves this module from the real filesystem at
  # import time, but llm-agents ships pi as a compiled bun binary with no dist/,
  # so it exists only inside the binary and the resolve throws — taking the whole
  # extension down with it. Point it at the clipboard package pi does ship
  # unpacked, and adapt the generated helper to that module's API.
  clipboardPkg = "${pi}/libexec/pi/node_modules/@mariozechner/clipboard";

  # --replace-fail: if a future pi-vim rewrites this file, fail the build loudly
  # rather than shipping an extension that silently no-ops.
  patched = runCommand "${pi-vim.name}-patched" {} ''
    cp -r ${pi-vim} $out
    chmod -R u+w $out

    if [ "${pi-vim.version}" != "${lastReviewed}" ]; then
      echo "pi-vim ${pi-vim.version} has not been reviewed against muru's patch (last reviewed: ${lastReviewed})." >&2
      echo "" >&2
      echo "Diff the new clipboard-mirror.ts against the --replace-fail needles in" >&2
      echo "apps/muru/plugins/pi-vim/default.nix, confirm the redirect to @mariozechner/clipboard" >&2
      echo "still makes sense, then put ${pi-vim.version} in apps/muru/plugins/pi-vim/last-reviewed." >&2
      exit 1
    fi

    # If a future pi release renames or drops this path, the substitutions
    # below still succeed (they don't reference it) and the build still
    # produces a working-looking extension — the failure would only surface
    # silently, at runtime, in a spawned child process whose stderr nothing
    # reads. Fail the build instead.
    test -e ${clipboardPkg}/index.js || {
      echo "pi no longer ships @mariozechner/clipboard at the expected path" >&2
      exit 1
    }

    substituteInPlace $out/clipboard-mirror.ts \
      --replace-fail 'import.meta.resolve(
  "@earendil-works/pi-coding-agent",
)' '"file://${clipboardPkg}/index.js"' \
      --replace-fail 'import { copyToClipboard } from ''${JSON.stringify(PI_CODING_AGENT_MODULE_URL)};' 'import clipboard from ''${JSON.stringify(PI_CODING_AGENT_MODULE_URL)};
const copyToClipboard = (text) => clipboard.setText(text);'
  '';
in
"${patched}/index.ts"
