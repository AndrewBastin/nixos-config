{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-06-27";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "4770a3467169bfdb0a3b11601921aaf27c100630";
    hash = "sha256-erZI0H5TxqFu2P917juL5PIB3LC0oJGKPcB1VibJDqo=";
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
