# Transform that swaps a PREBUILT native (Zig) module into nixpkgs' `ghostel`
# Emacs package.
#
# nixpkgs' `ghostel` Emacs package compiles its native module from source with
# Zig.  That build links libghostty, whose `build.zig` probes for the macOS SDK
# via `std.zig.LibCInstallation.findNative`; inside the Nix sandbox on Darwin no
# Apple SDK is reachable, so it fails with `error.DarwinSdkNotFound` and the
# whole build crashes (this is effectively a nixpkgs darwin packaging bug).
#
# This file returns a function `elisp -> elisp'` that overrides the package's
# `preBuild` to install a prebuilt release asset instead of building the module,
# dropping the dependency on the from-source Zig build entirely.  The package's
# own `files` directive still installs `ghostel-module<ext>` from the build dir
# into the Elisp output, where the loader finds it next to ghostel.el
# (`ghostel--module-directory`).
#
# Apply it over the whole Emacs package scope (see ./default.nix) so dependents
# like `evil-ghostel`, whose `ghostel` dependency resolves to this same package,
# pick up the prebuilt module too.
{ lib
, stdenv
, fetchurl
}:

let
  # Prebuilt native module release.  nixpkgs' Elisp is pinned to the v0.34.0 era
  # (rev f7800f6, whose `ghostel--minimum-module-version` is "0.34.0"), so the
  # matching v0.34.0 module satisfies the loader's post-load version check.  This
  # is pinned independently of the Elisp's nix version string
  # ("0.34.0-unstable-...", which is not a real release tag and so cannot drive
  # an asset URL).
  moduleVersion = "0.34.0";

  # Map each supported system to its release asset.  Hashes are for the
  # v${moduleVersion} release.
  modules = {
    x86_64-linux = {
      asset = "ghostel-module-x86_64-linux.so";
      hash = "sha256-VhuKgSi/GszlalJjUMfvBWycDJEzutuf6g1hu165QyE=";
    };
    aarch64-linux = {
      asset = "ghostel-module-aarch64-linux.so";
      hash = "sha256-1ZaFFmLAwY/mYLbaim16zEp0bHGousjrS/WoJldyrFo=";
    };
    x86_64-darwin = {
      asset = "ghostel-module-x86_64-macos.dylib";
      hash = "sha256-3+DbexbhTfgYUIrz78R8TyJOD1tDOsc2J3dYahCLr9Q=";
    };
    aarch64-darwin = {
      asset = "ghostel-module-aarch64-macos.dylib";
      hash = "sha256-z7mTLgaf+c2hXWQrO8P1yUni6Yok6MRznXDwPS8j1qg=";
    };
  };

  system = stdenv.hostPlatform.system;
  module = modules.${system} or
    (throw "ghostel: no prebuilt native module for system ${system}");

  prebuiltModule = fetchurl {
    url = "https://github.com/dakra/ghostel/releases/download/v${moduleVersion}/${module.asset}";
    inherit (module) hash;
  };

  libExt = stdenv.hostPlatform.extensions.sharedLibrary;
in
elisp: elisp.overrideAttrs (_: {
  # nixpkgs builds `ghostel-module${libExt}` from source here (via its `module`
  # derivation); swap in the prebuilt asset so no Zig build runs.  Replacing
  # `preBuild` removes the only build-time reference to that Zig derivation.
  preBuild = ''
    install -m444 ${prebuiltModule} ghostel-module${libExt}
  '';
})
