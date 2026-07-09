{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.205-unstable-2026-07-08";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "be02c39841a59e2ac1f35ac12285def02acdbb5a";
    hash = "sha256-b9S1l82jKlimJ4/EITDdTZW4OaZvWazJy5CdHDMhTk8=";
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
