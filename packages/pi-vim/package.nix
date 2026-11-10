{
  lib,
  stdenvNoCC,
  fetchzip,
  nix-update-script,
}:

let
  version = "0.16.0";
in
stdenvNoCC.mkDerivation {
  pname = "pi-vim";
  inherit version;

  src = fetchzip {
    name = "pi-vim-${version}-source";
    url = "https://registry.npmjs.org/pi-vim/-/pi-vim-${version}.tgz";
    hash = "sha256-Ef7KOS40+cYRyEEqUvAYrAGmQE40Hr+7HeddUlXRpnc=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Vim keybindings extension for pi coding agent";
    homepage = "https://www.npmjs.com/package/pi-vim";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
