{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "0-unstable-2026-06-02";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "bdb04fc52421537f63bbcb9685e1c0905689f8f7";
    hash = "sha256-GG5HsRw3TGIjLEzBGsG1IGa+jRnCXz5FhY2R4cLE1/s=";
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
