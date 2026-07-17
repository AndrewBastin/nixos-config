{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.212-unstable-2026-07-17";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "67f390c9a0b1440d369aebe2ff6a5023db35bf8e";
    hash = "sha256-7Rbw2MzJcDRCqpCWqGJTYfbLUoq8NcSKROtA3x/JlmI=";
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
