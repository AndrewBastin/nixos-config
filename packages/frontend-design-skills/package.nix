{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.168-unstable-2026-06-06";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "72281753c2af394d35d6950af5980832cbebd322";
    hash = "sha256-XjXv1uuVJnHgizdTcilhjNeccPP4y1modMXTGlWqeV8=";
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
