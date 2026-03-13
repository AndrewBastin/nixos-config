{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-03-13";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "9511cb09cadcbf57e39a46b06a52d00957177175";
    hash = "sha256-3RR8mi7CcVMDMitdTdaonFmfAIkeOzWK/CVKQmomIhE=";
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
