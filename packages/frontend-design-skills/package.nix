{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.198-unstable-2026-07-01";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "75709eacf1334051ea293fb87a0e88a1e6812f94";
    hash = "sha256-5ubOnXBa8oFii+gbi3vBksb34I7CW2UWRPD3JFn45JY=";
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
