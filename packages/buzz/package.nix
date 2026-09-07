# Buzz desktop (https://github.com/block/buzz) installed from the official
# amd64 .deb. It's a Tauri app, so the deb's ELF expects FHS system libs
# (libwebkit2gtk-4.1, gtk3, ...); autoPatchelfHook rewrites it to point at the
# nix store equivalents instead.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  webkitgtk_4_1,
  gtk3,
  gdk-pixbuf,
  alsa-lib,
  openssl,
  glib-networking,
  gst_all_1,
  # Tray icon support: buzz-desktop dlopens the appindicator lib at runtime,
  # so it needs to be on the binary's rpath rather than in buildInputs.
  libayatana-appindicator,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "buzz";
  version = "0.5.23";

  src = fetchurl {
    url = "https://github.com/block/buzz/releases/download/desktop-v0.5.23/Buzz_0.5.23_amd64.deb";
    hash = "sha256-lPHlACH4j4hk9WjIao6is5mT2mTj/o2Gv3Mc0AwcnM4=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
  ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
    gdk-pixbuf
    alsa-lib
    openssl
    glib-networking
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
  ];

  # Only ships x86_64 Linux binaries; keep the build from trying to patch the
  # .desktop/icons tree.
  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    mv usr/bin $out/bin
    mv usr/share $out/share

    runHook postInstall
  '';

  postFixup = ''
    add-rpath() { patchelf --add-rpath "$2" "$1"; }
    add-rpath $out/bin/buzz-desktop ${lib.makeLibraryPath [ libayatana-appindicator ]}
  '';

  meta = with lib; {
    description = "Buzz desktop app — your conversations, agents, and forums";
    homepage = "https://github.com/block/buzz";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "buzz-desktop";
  };
})
