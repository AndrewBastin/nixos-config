{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.191-unstable-2026-06-24";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "0bd954331e2dbf76024ac53b0fd997314f653e51";
    hash = "sha256-FoOfXbGL4UdNFM+IXN698E+t5iK/XxoxpzT7oKlZMQ0=";
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
