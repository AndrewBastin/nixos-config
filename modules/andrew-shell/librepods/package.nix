# Builds librepods (linux/rust branch) using naersk. Pure-D-Bus BlueZ access
# (via the `bluer` crate) means no libbluetooth at build or runtime. The GUI
# and system-tray have been stripped; only the IPC daemon remains.
{ callPackage
, naersk-input
, lib
, pkg-config
, dbus
, libpulseaudio
}:

let
  naersk = callPackage ../shell/utils/naersk.nix { inherit naersk-input; };
in
  naersk.buildPackage {
    src = ./source;

    nativeBuildInputs = [ pkg-config ];

    buildInputs = [
      dbus
      libpulseaudio
    ];

    meta = with lib; {
      description = "AirPods control on Linux (vendored from kavishdevar/librepods linux/rust branch)";
      homepage = "https://github.com/kavishdevar/librepods";
      license = licenses.agpl3Only;
      mainProgram = "librepods";
      platforms = platforms.linux;
    };
  }
