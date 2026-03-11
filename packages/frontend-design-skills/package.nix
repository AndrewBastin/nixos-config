{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.72-unstable-2026-03-10";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "f6dbf44cd5f5a90f8fd2608c13f3d7bcf15bfe6f";
    hash = "sha256-OuXzqIGJvSlIULaqwfjxr1C60dDrOGbGXPLupvperIU=";
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
