{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-prompts";
  version = "5.0.7-unstable-2026-04-24";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "6efe32c9e2dd002d0c394e861e0529675d1ab32e";
    hash = "sha256-0WupTacT1jIwVBloj1i0RF7wIllVtP8eMPRl7VrXdbE=";
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
