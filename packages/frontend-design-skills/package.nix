{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.69-unstable-2026-03-05";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "9582ad480f687bbeaf0025852ac4f020b07f20bb";
    hash = "sha256-LrQ8Gj46BFkKDr+KZ+DT/fnaS4uehXiX44D3N+/EqQg=";
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
