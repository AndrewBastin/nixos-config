{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-03-03";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "c02c804bb7c8873da8182745654fb57dc63b7348";
    hash = "sha256-ZXJx4iwGCAi6qqDiLSuJvX3UL6XzypxSO7ptspDD/Yw=";
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
