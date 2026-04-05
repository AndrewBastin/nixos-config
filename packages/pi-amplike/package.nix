{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "pi-amplike";
  version = "1.3.4";

  src = fetchurl {
    url = "https://registry.npmjs.org/pi-amplike/-/pi-amplike-1.3.4.tgz";
    hash = "sha256-/Spzt1wPAOK2nRb7w3zmvtMa5slXam59WWQUxyTh/mE=";
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
    description = "Pi skills and extensions that provide Amp Code-like workflows (handoff, permissions, mode selector, web access)";
    homepage = "https://github.com/pasky/pi-amplike";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
