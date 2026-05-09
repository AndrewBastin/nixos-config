{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.138-unstable-2026-05-09";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "831608a360511febd4b10c77d4d03b47afda2f5b";
    hash = "sha256-ab/VKJRTCpF6IbjdSEZxySv2jXJZvyOotHMcKLdNZy8=";
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
