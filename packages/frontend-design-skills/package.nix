{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
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
