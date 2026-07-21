{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.216-unstable-2026-07-20";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "4d07874235b765871f39227c823f91aa989934ea";
    hash = "sha256-vtXv+x4qJX0TIcZUwIVjsIiKKY21vXVLe7jNgBThh40=";
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
