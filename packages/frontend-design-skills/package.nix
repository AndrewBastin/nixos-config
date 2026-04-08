{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.94-unstable-2026-04-07";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "b9fbc7796b80659c570265deee97b0a8fc40bd89";
    hash = "sha256-stNnM9VQuJDrxz9vuNFjz+ldKHj7LZzfpvnHJv0o1Kw=";
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
