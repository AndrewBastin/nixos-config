{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "0-unstable-2026-06-02";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "625c04c3350378c3d74662505aae3e9dcf3fa1b4";
    hash = "sha256-3sYBc6rP6FUO6xocIVYGG4Mf2wqYuNwhJjRyWux8kkk=";
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
