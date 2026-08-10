{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-08-07";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "be0b21d0873092a63946cc2678dd700aac945902";
    hash = "sha256-Dy73TfcrcbCXY9lwDszNgAKLiCAHf1KIwC4Q5U6k21E=";
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
