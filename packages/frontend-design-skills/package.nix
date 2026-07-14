{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.209-unstable-2026-07-14";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "988b3e56432775c09bba903ba22522b97cd0f2fb";
    hash = "sha256-zk0ITtjvwYDDdbHv+iPl0G/4b3OKZx7Cjx49KtPR2z0=";
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
