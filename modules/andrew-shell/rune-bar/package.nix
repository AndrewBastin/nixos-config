# The Rune-rendered bar (andrew-bar), built with the `dist` profile (fat LTO). `extraPath` is
# the programs it runs (helpers, nmcli, wpctl, …); they go after the session's PATH.
{ lib, rustPlatform, pkg-config, makeWrapper, wayland, libxkbcommon, vulkan-loader, extraPath ? [ ] }:

rustPlatform.buildRustPackage {
  pname = "andrew-bar";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./bar ./vendor ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  buildType = "dist";
  cargoBuildFlags = [ "-p" "andrew-bar" ];
  # The tests build the whole bar again under `dist`; they run in development instead.
  doCheck = false;

  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ wayland libxkbcommon ];

  # wgpu and winit dlopen Vulkan, Wayland and xkbcommon.
  postFixup = ''
    wrapProgram $out/bin/andrew-bar \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vulkan-loader wayland libxkbcommon ]} \
      --suffix PATH : ${lib.makeBinPath extraPath}
  '';

  meta.mainProgram = "andrew-bar";
}
