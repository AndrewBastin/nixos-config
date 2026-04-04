{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.92-unstable-2026-04-04";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "b543a256248ce5ff98804b8dfef4cd6247423d98";
    hash = "sha256-DNRiSbJR77PjLIMK7BC/LN9A1g7q9NPybnPLxngvh9o=";
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
