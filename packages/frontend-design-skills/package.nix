{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.139-unstable-2026-05-11";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "fdfbc06c7a6d9ace49c55b3761b1be05d276da6d";
    hash = "sha256-1Id0esxDUikoEP8A5S2Ef3v7uEScnS3cHo2jn2bdzj0=";
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
