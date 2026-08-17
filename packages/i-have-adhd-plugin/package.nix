{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "i-have-adhd-plugin";
  version = "0-unstable-2026-08-18";

  src = fetchFromGitHub {
    owner = "ayghri";
    repo = "i-have-adhd";
    rev = "1fa9c7cc4b8a4e1e247388d213214bdc83ce8e67";
    hash = "sha256-qkMHSn5/dka10iMzk5A0AGgwkknQROH3Wp5qwwfvuyg=";
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
