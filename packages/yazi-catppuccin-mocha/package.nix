{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-08-22";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "20b47bfd78880c2674899597fd26bc01b21ff48c";
    hash = "sha256-NGnfrQdsnQITKCZ0oh6DCxeCR2ozJoPAZetsi3ghHAI=";
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
