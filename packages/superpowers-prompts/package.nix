{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-prompts";
  version = "5.0.7-unstable-2026-04-02";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "b7a8f76985f1e93e75dd2f2a3b424dc731bd9d37";
    hash = "sha256-hGEMwmSojy3cNtUQvB5djExlD39O2dwcnLOMUNaVIHg=";
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
