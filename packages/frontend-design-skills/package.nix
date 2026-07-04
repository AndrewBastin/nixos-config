{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.201-unstable-2026-07-03";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "c489eb25c7e32dec227916e1663cab3538ba594d";
    hash = "sha256-2HzcrlulegtmDMTe53GsabhfvXeFMZzI1r5io13eNPo=";
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
