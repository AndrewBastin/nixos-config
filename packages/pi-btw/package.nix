{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "pi-btw";
  version = "0.2.1-unstable-2026-04-04";

  src = fetchFromGitHub {
    owner = "dbachelder";
    repo = "pi-btw";
    rev = "cb1be6c9c4e8611969e1c1574e320e7231e8aef6";
    hash = "sha256-CMiA6ubA+GsvEo8WwCTY3BtucHVjHAPwbPeSTLd6KaA=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    rm -rf $out/.git $out/.github
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "pi-btw — parallel side conversations extension and skill for pi";
    homepage = "https://github.com/dbachelder/pi-btw";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
