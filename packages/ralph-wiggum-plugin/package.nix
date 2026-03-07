{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "2.1.71-unstable-2026-03-07";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "53a5f3ee0703c2ab1b6d1dd18d8ab65187f9b8ad";
    hash = "sha256-GY/S9cPYd/Vu9u0OLvn2S0r5I4J+PuVSVE54i55YegM=";
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
