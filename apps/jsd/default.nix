# jsd — run Node apps and tests with Chrome DevTools opening on `debugger` statements.
# See docs in src/jsd.js (usage) — `jsd -- <command>` is the main entry point.
#
# Linux only: DevTools windows come from nixpkgs Chromium, used only for that.
# Uses callPackage convention.
{
  lib,
  runCommand,
  makeWrapper,
  nodejs_24,
  chromium,
}:

runCommand "jsd" {
  nativeBuildInputs = [ makeWrapper ];
  meta = {
    description = "Node debugger launcher: DevTools opens on `debugger`";
    platforms = lib.platforms.linux;
    mainProgram = "jsd";
  };
} ''
  mkdir -p $out/lib
  cp -r ${./src} $out/lib/jsd
  makeWrapper ${nodejs_24}/bin/node $out/bin/jsd \
    --add-flags $out/lib/jsd/jsd.js \
    --set-default JSD_CHROMIUM ${chromium}/bin/chromium
''
