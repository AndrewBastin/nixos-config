{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "0-unstable-2026-05-31";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "8bae02d5319c619f84f51476188e5b28b2e5816b";
    hash = "sha256-0zOI9h29AzvoQLGXb8PMzULMbfRLNNREKXTZ/jFUjPc=";
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
