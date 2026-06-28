{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.195-unstable-2026-06-26";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "01f1617f14452ac78bf319cef2236d87c0fe05cb";
    hash = "sha256-eVdDeXy/+Tbwv4JvSSdS4rTwvEIvV3gidUw9PSRReWw=";
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
