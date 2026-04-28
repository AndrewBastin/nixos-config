{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.121-unstable-2026-04-28";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "158620419486e3d2d696351d5a71fbd6b8f58653";
    hash = "sha256-VijUfLt1+ancqgbsQvpKvdlayxhKvyn4JB5sy3X8NoY=";
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
