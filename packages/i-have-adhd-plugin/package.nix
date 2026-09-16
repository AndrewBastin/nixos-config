{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "i-have-adhd-plugin";
  version = "0-unstable-2026-09-15";

  src = fetchFromGitHub {
    owner = "ayghri";
    repo = "i-have-adhd";
    rev = "0a84de401019a3a822248df586d88a2b56f8c6af";
    hash = "sha256-p5TYNh1/VYP0WMFAkofsqzIXKWcmvWD3adPz94I/Yu8=";
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
