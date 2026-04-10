{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "2.1.98-unstable-2026-04-09";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "c5600e0b1e9bb6ddf750cf7441c4d4fffbb7c917";
    hash = "sha256-NCE3yvf8UlEHfFo7U6VcREmzSqKZ23aNIaJMbK/sepo=";
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
