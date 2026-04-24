{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "2.1.119-unstable-2026-04-23";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "ab3ce06c9ac0a6a0405850e642b80b0bb2c9fb25";
    hash = "sha256-Y8wAKKd+PB5YvSUtzBR2BPL37PyD0oXIdTud1uo5xwg=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r plugins/ralph-wiggum $out
    chmod +x $out/hooks/stop-hook.sh $out/scripts/setup-ralph-loop.sh
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Ralph Wiggum loop plugin for Claude Code — self-referential agentic loops";
    homepage = "https://github.com/anthropics/claude-code";
    platforms = platforms.all;
  };
}
