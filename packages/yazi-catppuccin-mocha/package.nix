{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-11-09";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "38c08d8eb9ea0d28c8c911a249a08f27ba2151ac";
    hash = "sha256-lITDt1QvL54u6gbJiGixPyP6lk72f3rkiNPDrUg6G8I=";
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
