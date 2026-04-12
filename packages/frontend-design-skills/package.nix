{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.104-unstable-2026-04-10";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "9772e13f820002c9730af67a2409702799c7ddc6";
    hash = "sha256-Ir8bikRS0YSwEE2IGtpHE7G1pe94V38h74ubatyM1GM=";
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
