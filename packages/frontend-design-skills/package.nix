{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.116-unstable-2026-04-20";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "fe53778ed90fd971bf4ec78fa1f65ccf0536352f";
    hash = "sha256-1BHp/6dmAydomw3a50ZGxHIpLhvLzEjP2/5ZtxbMg6I=";
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
