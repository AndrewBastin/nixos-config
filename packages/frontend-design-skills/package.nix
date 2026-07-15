{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.210-unstable-2026-07-14";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "b7784f2c63ed4585c32bc20b94d3b64cf4fe6df3";
    hash = "sha256-jb6SQOzQyYLoBoXMW1A2iTKFh/Z457/iJ/z7YPj4ri4=";
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
