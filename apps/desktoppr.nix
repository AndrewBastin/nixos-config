{
  lib,
  stdenv,
  fetchurl,
  unzip
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "desktoppr";
  version = "0.5";

  src = fetchurl {
    url = "https://github.com/scriptingosx/desktoppr/releases/download/v${finalAttrs.version}/desktoppr-${finalAttrs.version}-218.zip";
    sha256 = "sha256-Oa9gAQjOaJHYyT5JBUiFCxL1sQP1dqlFBm+GdmLHNNM=";
  };

  nativeBuildInputs = [ unzip ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    
    install -D -m755 desktoppr $out/bin/desktoppr
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "Simple command line tool to set the desktop picture on macOS";
    longDescription = ''
      Desktoppr is a simple command line tool to set the desktop picture/wallpaper on macOS.
      It can set wallpapers from local files or download them from URLs.
      Supports multiple displays and various scaling options.
    '';
    homepage = "https://github.com/scriptingosx/desktoppr";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = [ "aarch64-darwin" "x86_64-darwin" ];
    mainProgram = "desktoppr";
  };
})