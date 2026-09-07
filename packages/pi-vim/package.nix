{
  lib,
  stdenvNoCC,
  fetchzip,
  nix-update-script,
}:

let
  version = "0.14.2";
in
stdenvNoCC.mkDerivation {
  pname = "pi-vim";
  inherit version;

  src = fetchzip {
    name = "pi-vim-${version}-source";
    url = "https://registry.npmjs.org/pi-vim/-/pi-vim-${version}.tgz";
    hash = "sha256-KiQYCdC6yr9PTZX2En53Eq4NT5rQ21aR+kGItRO7WbU=";
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
