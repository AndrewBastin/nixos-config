{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.183-unstable-2026-06-19";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "c487902a53fc25aea01ddfdf2bf002e82d0cad45";
    hash = "sha256-60Fzzr25NiOa09uPD0YiDL4HgPlbjPo+lHU9ZDJg9gQ=";
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
