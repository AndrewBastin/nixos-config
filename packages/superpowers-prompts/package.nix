{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-prompts";
  version = "5.0.7-unstable-2026-04-15";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "c4bbe651cb1bc5e7bec6f7effae2b946571f3258";
    hash = "sha256-P2p3jimioQ5OSnwiM7tI+nX1b4xBv7UQ/3bg+c9AyTg=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r commands $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Superpowers prompt templates for pi coding agent";
    homepage = "https://github.com/obra/superpowers";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
