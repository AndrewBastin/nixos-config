{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.148-unstable-2026-05-22";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "2194e8e0904087b9f2afce41a2ec083cc71c0653";
    hash = "sha256-5eadGqp0C1LyV75UxtfZ3v/fuUgDjGsJ6GA6Xrm2e1E=";
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
