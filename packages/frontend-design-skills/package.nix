{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.214-unstable-2026-07-18";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "07dcb0e13580b21174ff1bf6a7e1d5ead3b61d60";
    hash = "sha256-eweeDHoogliCUpRJ6uWmpl0miHrX8FaHFuIZxhNTCDA=";
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
