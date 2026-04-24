{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.119-unstable-2026-04-23";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "ab3ce06c9ac0a6a0405850e642b80b0bb2c9fb25";
    hash = "sha256-Y8wAKKd+PB5YvSUtzBR2BPL37PyD0oXIdTud1uo5xwg=";
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
