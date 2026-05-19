{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.144-unstable-2026-05-19";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "69d707009ec5a9362ea3552b0580d0f658428f0a";
    hash = "sha256-sSHTLxcH8Hr8wltetAI4Pi/pmh/41ctLbBFa2rmyLIE=";
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
