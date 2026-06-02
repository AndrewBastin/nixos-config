{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
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
    cp -r plugins/frontend-design/skills $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Frontend design skills for AI coding assistants from Claude Code";
    homepage = "https://github.com/anthropics/claude-code";
    platforms = platforms.all;
  };
}
