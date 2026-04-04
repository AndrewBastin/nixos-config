{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "pi-vim";
  version = "0.3.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/pi-vim/-/pi-vim-0.3.2.tgz";
    hash = "sha256-QOZ4a7VD5MgihJZHJU4QGx3oW4lsul+9bVmYyUlknxg=";
  };

  dontBuild = true;

  unpackPhase = ''
    mkdir -p source
    tar xzf $src --strip-components=1 -C source
  '';

  installPhase = ''
    runHook preInstall
    cp -r source $out
    runHook postInstall
  '';

  meta = with lib; {
    description = "Vim keybindings extension for pi coding agent";
    homepage = "https://www.npmjs.com/package/pi-vim";
    platforms = platforms.all;
  };
}
