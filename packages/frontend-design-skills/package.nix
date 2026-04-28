{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.123-unstable-2026-04-29";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "e512ec99188d191b07662fc9f69c5764f750a302";
    hash = "sha256-O66x6qxUk/qmEXS0USORS2nhfvHdP/2cbj7RJ6bPhqY=";
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
