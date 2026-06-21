{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.185-unstable-2026-06-20";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "b4073894cdef365c6061f036098ce0875bbdbc86";
    hash = "sha256-8mtiItHlBQcVcjT59+9wrwOmN1Ih6qKhsGJk/zQjP0A=";
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
