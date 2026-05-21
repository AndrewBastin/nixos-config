{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.146-unstable-2026-05-21";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "1573399b48ff00e9dedf2ce898021dd2f48b6b97";
    hash = "sha256-QXAi2lilpvLh2y29FifyptpkkU7qYitunrVJSFjUpFA=";
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
