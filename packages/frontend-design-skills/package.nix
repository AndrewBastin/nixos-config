{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.110-unstable-2026-04-16";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "5a7bf281bab3a1bf37245ea84000b4936322eefa";
    hash = "sha256-m0fV7m/NPuuIoS03yyZVLnpC1Fw+UHGM6FmD86UN4zc=";
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
