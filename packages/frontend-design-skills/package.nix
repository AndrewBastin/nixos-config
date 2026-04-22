{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.117-unstable-2026-04-22";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "2fa67717b8046c253cfa55fd84002e3501f1eca6";
    hash = "sha256-KQJC5qri7JsmivqLTGz/xQ7yueUmHzYmUhV0mtUzLbM=";
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
