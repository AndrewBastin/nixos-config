{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.145-unstable-2026-05-19";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "cc898dc3692fb583f36ab327942aad20b7d3dbd0";
    hash = "sha256-KzNWJ4Qz6kPmIB98cdRwtAiBU/oFHhn+9JATNVag44E=";
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
