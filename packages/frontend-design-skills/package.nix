{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.220-unstable-2026-07-25";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "7ef6eec9d9ba84ea6f233f26c45f1df5c5991843";
    hash = "sha256-E18pPkdErB133CIShgLBhdHBiyPALuRl30uOqhy21v0=";
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
