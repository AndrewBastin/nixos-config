{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "yazi-catppuccin-mocha";
  version = "0-unstable-2026-05-16";

  src = fetchFromGitHub {
    owner = "yazi-rs";
    repo = "flavors";
    rev = "54ab389e4deb3d1bc1d8de18d99e825962a55da1";
    hash = "sha256-46x4K4dx4rlU108SXhctJOeGlO/W57Pnofb914Sa4vA=";
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
