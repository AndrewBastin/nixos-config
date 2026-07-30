{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-07-28";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "1a5f7877c770ff4db380b0b78e0e1a2cb4206103";
    hash = "sha256-rEoCpbb1wmvzJJXtQ6dDkBIUw/W3VWwJGBkjWhYTgYk=";
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
