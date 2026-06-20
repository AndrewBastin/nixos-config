# Native (Zig) module for ghostel, fetched as a prebuilt GitHub release asset.
#
# ghostel ships its Elisp on MELPA and the matching native module as per-platform
# assets on its GitHub releases.  We take the Elisp from melpaStablePackages
# (versioned from the git tag, e.g. "0.35.4") so the version lines up with a real
# release tag and the module + Elisp stay in lockstep.  melpaPackages, by
# contrast, is a date snapshot ("20260619.1010") that matches no release tag and
# so cannot drive the asset URL.
#
# `emacs` is expected to be the same Emacs the dev shell builds with (so the
# module's version tracks the Elisp it will load); pass it explicitly via
# callPackage, e.g. `callPackage ./nix/ghostel.nix { emacs = pkgs.emacs-pgtk; }`.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, emacs
}:

let
  elisp = emacs.pkgs.melpaStablePackages.ghostel;
  version = elisp.version;

  # Map each supported system to its release asset and the Emacs module suffix
  # (`module-file-suffix`) ghostel expects on disk.  Hashes are for the
  # v${version} release.
  modules = {
    x86_64-linux = {
      asset = "ghostel-module-x86_64-linux.so";
      suffix = ".so";
      hash = "sha256-YLjXEWJV7/LsRTT/RNb2xr48A0KInHxq2vtKksx9lZc=";
    };
    aarch64-linux = {
      asset = "ghostel-module-aarch64-linux.so";
      suffix = ".so";
      hash = "sha256-dk/zoeBIeXUq5QC14QpAFnjs6rRR75UcPP/lByoGMFc=";
    };
    x86_64-darwin = {
      asset = "ghostel-module-x86_64-macos.dylib";
      suffix = ".dylib";
      hash = "sha256-Tkmkv3WGQogTav84C50IprqfQgtg2+LSFgfh7b71s5o=";
    };
    aarch64-darwin = {
      asset = "ghostel-module-aarch64-macos.dylib";
      suffix = ".dylib";
      hash = "sha256-V/7LxPhHLidRQmUvYkK1c2C+RHm0mvnOSp8VUNBphX0=";
    };
  };

  system = stdenv.hostPlatform.system;
  module = modules.${system} or
    (throw "ghostel: no prebuilt native module for system ${system}");
in
stdenv.mkDerivation {
  pname = "ghostel-native-module";
  inherit version;

  src = fetchurl {
    url = "https://github.com/dakra/ghostel/releases/download/v${version}/${module.asset}";
    inherit (module) hash;
  };

  dontUnpack = true;

  # autoPatchelfHook is Linux/ELF only; the macOS .dylib needs neither.
  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib ];

  installPhase = /* sh */ ''
    runHook preInstall

    install -Dm644 "$src" "$out/lib/ghostel/ghostel-module${module.suffix}"

    # Sidecar version file ghostel reads to gate `module-load` (must be
    # >= ghostel--minimum-module-version, which tracks the Elisp).
    printf '%s\n' "${version}" > "$out/lib/ghostel/ghostel-module.version"

    runHook postInstall
  '';

  # Expose the matching Elisp so callers keep a single source of truth for the
  # version and can put it on the Emacs load path in lockstep with the module.
  passthru = { inherit elisp; };

  meta = {
    description = "Prebuilt native (Zig) module for the ghostel Emacs package";
    homepage = "https://github.com/dakra/ghostel";
    platforms = builtins.attrNames modules;
  };
}
