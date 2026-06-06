{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.167-unstable-2026-06-06";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "c1b75cba5e990e643ed62db6769a9f9807bdb053";
    hash = "sha256-Zwvfb8FIQFK5mOr4N5rK1pwkaghxnn51BObS4X9y/fQ=";
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
