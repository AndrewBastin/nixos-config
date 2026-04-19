{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-prompts";
  version = "5.0.7-unstable-2026-04-16";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "b55764852ac78870e65c6565fb585b6cd8b3c5c9";
    hash = "sha256-cobQloF7Y6K0IC0/6xSnA2Io+fKgk2SRmCwoZZtVCco=";
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
