# pi-vim — Vim keybindings extension for pi, patched for muru.
#
# pi-vim mirrors the vim register to the system clipboard by spawning a child
# helper for every clipboard read/write. The child is assumed to be a JS runtime
# (`process.execPath`) importing a clipboard module resolved from pi's install.
# Neither assumption holds for llm-agents' pi: it is a bun-compiled binary that
# rejects `-e` ("Unknown option: --input-type"), and it no longer ships a
# @mariozechner/clipboard package to resolve. Run the helper with node instead,
# and point it at a shim that drives the platform clipboard tools pi itself uses.
#
# Returns the entry point to pass to pi's -e flag.
{
  lib,
  runCommand,
  callPackage,
  pi,
  nodejs,
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

  # The module the generated helper imports instead of pi's coding-agent package.
  # It answers to the @mariozechner/clipboard shape pi-vim expects (default
  # export with setText for writes; hasText/getText for reads) so the only patch
  # to clipboard-mirror.ts is the module URL, not its logic.
  clipboardShim = runCommand "pi-vim-clipboard-shim" { } ''
    mkdir -p $out/node_modules/@mariozechner/clipboard
    cp ${./clipboard-shim.js} $out/node_modules/@mariozechner/clipboard/index.js
    cat > $out/node_modules/@mariozechner/clipboard/package.json <<'EOF'
    { "name": "@mariozechner/clipboard", "version": "0.0.0", "main": "index.js" }
    EOF
  '';
  clipboardPkg = "${clipboardShim}/node_modules/@mariozechner/clipboard";

  # --replace-fail: if a future pi-vim rewrites this file, fail the build loudly
  # rather than shipping an extension that silently no-ops.
  patched = runCommand "${pi-vim.name}-patched" { } ''
    cp -r ${pi-vim} $out
    chmod -R u+w $out

    if [ "${pi-vim.version}" != "${lastReviewed}" ]; then
      echo "pi-vim ${pi-vim.version} has not been reviewed against muru's patch (last reviewed: ${lastReviewed})." >&2
      echo "" >&2
      echo "Diff the new clipboard-mirror.ts against the --replace-fail needles in" >&2
      echo "apps/muru/plugins/pi-vim/default.nix, confirm running the helper with node" >&2
      echo "and the clipboard shim still makes sense, then put ${pi-vim.version} in" >&2
      echo "apps/muru/plugins/pi-vim/last-reviewed." >&2
      exit 1
    fi

    substituteInPlace $out/clipboard-mirror.ts \
      --replace-fail 'return import.meta.resolve("@earendil-works/pi-coding-agent");' 'return "file://${clipboardPkg}/index.js";' \
      --replace-fail 'process.execPath' '"${nodejs}/bin/node"' \
      --replace-fail 'import { copyToClipboard } from ''${JSON.stringify(moduleUrl)};' 'import clipboard from ''${JSON.stringify(moduleUrl)};
const copyToClipboard = (text) => clipboard.setText(text);'
  '';
in
"${patched}/index.ts"
