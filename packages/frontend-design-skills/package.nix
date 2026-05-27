{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.152-unstable-2026-05-27";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "b7339920b69f4a395c28727a1e2305dc5b122cb2";
    hash = "sha256-hlWSOcvHIMk9OJo6ZoPAAofU922Clj67oerFxIjLsIc=";
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
