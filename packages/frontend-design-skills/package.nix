{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.120-unstable-2026-04-25";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "7e936457e4e3899460b2be2f2b9b9f0b0174e859";
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
