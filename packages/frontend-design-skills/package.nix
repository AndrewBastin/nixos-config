{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.179-unstable-2026-06-16";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "843959fad9c3e5977c6295397da88df81604c94c";
    hash = "sha256-e6oMwzICcSnfe4zI0FfPi6XNJAdx1ucKKbGq9BK4Az0=";
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
