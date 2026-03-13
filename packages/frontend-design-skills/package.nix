{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.74-unstable-2026-03-12";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "2dc1e697836e94f3e9b7b8f19e6fb4a3622e3cca";
    hash = "sha256-zA8XbkO+citd27qQmPRZuIaDRCnrNuLgkpjR46aEvQk=";
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
