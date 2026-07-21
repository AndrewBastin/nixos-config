{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.217-unstable-2026-07-21";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "ac062f33ab0ca7c62b9df648d0f2027fa9b969f0";
    hash = "sha256-RD7k5ll455wvi4nJaXNIFglObqJWwrBrbPiXfG1EeDU=";
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
