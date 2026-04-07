{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-prompts";
  version = "5.0.7-unstable-2026-04-06";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "917e5f53b16b115b70a3a355ed5f4993b9f8b73d";
    hash = "sha256-FMaX6VMBC64OPdvXwhXKfHKnkdvdC2R9lZaU3BR/G3o=";
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
