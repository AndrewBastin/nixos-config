{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.79-unstable-2026-03-18";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "5e34f198d0f617de8679b69c50c421ae973d3466";
    hash = "sha256-PeWUDXY0aG6h7hCBVX4nLFkBWW57rt/SKFK9wEv1RzA=";
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
