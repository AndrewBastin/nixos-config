{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.207-unstable-2026-07-11";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "d4d8fbbb333c627d8fe2c1c583a5ccc26fdb1aed";
    hash = "sha256-fVtZ5SpQO75FKHgRXWQwImFoCg5pwRWbrzkIQ7RDQPY=";
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
