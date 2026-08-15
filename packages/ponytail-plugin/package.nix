{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ponytail-plugin";
  version = "4.9.0";

  src = fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    # v4.8.4
    rev = "bc9ee949d5f439e8b9f3bb92c6d6d3d1e6ebd324";
    hash = "sha256-1A9GkjCuiqwd6Wxl18CZUGYekxrbeTLVDapNUua8ihg=";
  };

  dontBuild = true;

  # Upstream ships the same ruleset for a dozen different agents. We only need
  # the Claude Code plugin surface (.claude-plugin + hooks + skills + commands)
  # and the pi extension surface (pi-extension + hooks + skills); everything else
  # is either another agent's packaging (.cursor, .windsurf, .opencode, …) or
  # repo scaffolding. The hooks are pure node scripts that write their state to
  # $CLAUDE_CONFIG_DIR / ~/.config/ponytail, never back into the plugin root, so
  # running them from the read-only store is fine.
  installPhase = ''
    runHook preInstall
    cp -r . $out
    rm -rf $out/.git $out/.github $out/tests $out/benchmarks $out/docs \
           $out/.cursor $out/.windsurf $out/.kiro $out/.clinerules \
           $out/.qoder $out/.qoder-plugin $out/.opencode $out/.openclaw \
           $out/.devin-plugin $out/ponytail-mcp $out/scripts
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Claude Code plugin enforcing lazy-senior-dev mode — YAGNI, stdlib first, no unrequested abstractions";
    homepage = "https://github.com/DietrichGebert/ponytail";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
