{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-04-09";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "06708015bfb53b169d99bb3907829f9175105d57";
    hash = "sha256-Gm6ThktOLUR+KDs6f3s1WCgrw2TOKQ4tolVvVdCxnCM=";
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
