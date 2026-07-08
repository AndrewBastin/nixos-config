{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.204-unstable-2026-07-08";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "d0f5bebd40c098c5913b6419a2ecfc7104f0cd41";
    hash = "sha256-IYDPW65fk0huxHFuwD5bmkL+YBCNNXLVRIQUQ64wg2Y=";
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
