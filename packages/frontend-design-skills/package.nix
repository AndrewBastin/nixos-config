{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.143-unstable-2026-05-15";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "8bdbb7296d3fa2217283d3ef94452dd64097393b";
    hash = "sha256-eyjtPpiYyxgY5tH8jldg8AfJQr2u+w1eIiCSQgAdgws=";
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
