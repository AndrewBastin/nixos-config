{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.177-unstable-2026-06-12";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "ca9f6045fc90c8244f9e787fb57d54b380f9a27c";
    hash = "sha256-ZizJ5+rkRiCGHc5FrluWD1lUnvS/rE0mDTpmp1sD4xM=";
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
