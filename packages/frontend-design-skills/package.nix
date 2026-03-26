{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.84-unstable-2026-03-26";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "a0d9b87038e72d8a523b61c152ec53299ac6fe94";
    hash = "sha256-j9TmGOt2FFnblg0ZlLvfWMYOXyiddWYlLE6E5AXiS/k=";
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
