{ lib, appimageTools, fetchurl }:

let
  pname = "paradev";
  version = "2.0.8";

  src = fetchurl {
    url = "https://github.com/ParadevAI/Paradev/releases/download/desktop-v${version}/superset-${version}-x86_64.AppImage";
    hash = "sha256-rUZB+e6rhFNIVaZPbBk1SWM38csSlWgeM8qvhoHMM+4=";
  };

  # Upstream still ships the Superset-branded binary/desktop/icon names.
  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm644 ${contents}/superset.desktop $out/share/applications/paradev.desktop
    install -Dm644 ${contents}/superset.png $out/share/icons/hicolor/512x512/apps/superset.png
    substituteInPlace $out/share/applications/paradev.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=paradev' \
      --replace-fail 'Exec=superset --new-window' 'Exec=paradev --new-window'
  '';

  meta = {
    description = "The last developer tool you'll ever need";
    homepage = "https://github.com/ParadevAI/Paradev";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "paradev";
  };
}
