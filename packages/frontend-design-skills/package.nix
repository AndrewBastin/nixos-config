{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.89-unstable-2026-04-01";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "b4fa5f85f3d2e02b47f67ab2e348ce6101fb7b5a";
    hash = "sha256-QvY9cFmAPbScxFS57QcEtyLg8h4X7rDE31UB2d04bvA=";
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
