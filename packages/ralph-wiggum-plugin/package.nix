{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "2.1.150-unstable-2026-05-23";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "39e853e4074d90f27afdfb7ea601e0fc378bd0c5";
    hash = "sha256-wBp8SlJ/4dxup/P584MM9nke5CtMtciPn5NvrEQr8iM=";
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
