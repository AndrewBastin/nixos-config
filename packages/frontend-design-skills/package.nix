{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.206-unstable-2026-07-09";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "15a21e1b4e240e2da6a4953d5f148a806c9c9bb2";
    hash = "sha256-9+PDgJyboouucf71gIpUrRenGAfwYmLdj+qfJfFrleE=";
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
