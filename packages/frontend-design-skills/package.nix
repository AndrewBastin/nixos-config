{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.76-unstable-2026-03-14";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "420a1884671fe09addc881f9a62624dae952d21c";
    hash = "sha256-1igZnEDoblQDOBPGeTF0C9bqCCmdhZeG1wMFmZNIq6I=";
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
