{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-09-29";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "1183892c904f7f0efdf4473e856ed308b7bea98d";
    hash = "sha256-E1OUF1+mT0V3crVxkewG2Y7hRu8fO+0oRl6NlINmw+o=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r catppuccin-mocha.yazi $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Catppuccin Mocha flavor for Yazi file manager";
    homepage = "https://github.com/yazi-rs/flavors";
    platforms = platforms.all;
  };
}
