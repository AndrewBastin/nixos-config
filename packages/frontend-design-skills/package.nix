{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.211-unstable-2026-07-15";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "c39cb0f14bfe8bb519bae5bfc55add6867c5e2ab";
    hash = "sha256-dSBhidXnPOCUTPa7z4fvovM0hbNCD0Lnu6o00sAlo3I=";
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
