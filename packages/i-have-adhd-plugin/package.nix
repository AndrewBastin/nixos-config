{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "i-have-adhd-plugin";
  version = "0-unstable-2026-08-10";

  src = fetchFromGitHub {
    owner = "ayghri";
    repo = "i-have-adhd";
    rev = "2ed064090711586e0c97a2fbbf15465fe8f1808b";
    hash = "sha256-/h4HxkUbtRGoqgyFvjJrd++XmOd1KSVku5dR2/f9b/s=";
  };

  dontBuild = true;

  # Same shape as ponytail: upstream ships one ruleset packaged for a dozen
  # agents, and we only keep the Claude Code surface (.claude-plugin + hooks +
  # skills). The SessionStart hook is opt-in — it no-ops unless
  # $CLAUDE_CONFIG_DIR/.i-have-adhd-always exists — and resolves SKILL.md
  # relative to $0, writing nothing back into the plugin root, so running it
  # from the read-only store is fine.
  installPhase = ''
    runHook preInstall
    cp -r . $out
    rm -rf $out/.git $out/.github $out/.cursor $out/.agents $out/.codex-plugin \
           $out/evals $out/tests $out/scripts \
           $out/GEMINI.md $out/gemini-extension.json $out/kimi.plugin.json
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { extraArgs = [ "--version=branch" ]; };

  meta = with lib; {
    description = "Claude Code plugin that shapes output for an ADHD reader — action first, numbered steps, no buried answers";
    homepage = "https://github.com/ayghri/i-have-adhd";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
