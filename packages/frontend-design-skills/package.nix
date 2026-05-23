{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.150-unstable-2026-05-23";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "39e853e4074d90f27afdfb7ea601e0fc378bd0c5";
    hash = "sha256-wBp8SlJ/4dxup/P584MM9nke5CtMtciPn5NvrEQr8iM=";
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
