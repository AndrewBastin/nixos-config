{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.175-unstable-2026-06-12";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "ee81682a72b07705672332d1dc963927a998c177";
    hash = "sha256-hgMewrcB+xQuWw1jYovfjFc2LYxI2+vcKITHEn/Wfrs=";
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
