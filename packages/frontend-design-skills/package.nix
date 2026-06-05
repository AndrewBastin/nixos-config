{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "0-unstable-2026-06-04";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "d1e174252d0af47174bd9fbdec6abb092b49226a";
    hash = "sha256-jY8DPVJkmYaS+j6vW3jpPiy9B6OrgPhA8HCfjDu29nI=";
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
