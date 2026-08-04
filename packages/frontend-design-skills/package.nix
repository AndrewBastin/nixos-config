{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.221-unstable-2026-08-04";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "dd796139237c9c105ffed1e2a40ea3a1faae9108";
    hash = "sha256-S2j8tUkSrE1TfsK+ix2RBWURhA/Gn7dG7rs14laG/ww=";
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
