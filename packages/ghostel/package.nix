# Ghostel, built from source with ALL its pieces pinned to ONE upstream rev.
#
# Why this exists (see also the drift story in apps/emacs/default.nix):
# ghostel and evil-ghostel live in the SAME repo (dakra/ghostel), but the usual
# packaging pulls them from two independently-moving channels — ghostel core from
# nixpkgs, evil-ghostel from the emacs-overlay's melpaStable set.  A routine
# `nix flake update' once advanced evil-ghostel 0.43 -> 0.44 while core stayed at
# 0.41; 0.44's redraw advice calls core's `ghostel--redraw' with an argument that
# only exists in >= 0.42.1, so the terminal broke on every repaint.
#
# Here a single `src' drives three derivations, so they can never desync:
#   * module        — the native (Zig) libghostty module + its version sidecar,
#   * ghostel (core)— the Elisp, with that module installed into it,
#   * evil-ghostel  — the Evil integration, whose `ghostel' dep is wired to the
#                     core built right here (not nixpkgs' copy).
# core + evil-ghostel are exposed together (evil-ghostel via passthru), so bumping
# ghostel is a one-line rev/hash change that moves all three at once.
#
# Bumping: `just bump' runs ./update.sh (see it) to follow the latest release tag,
# refreshing `src' AND the vendored Zig `module.deps' hash in lockstep.
#
# Modeled on nixpkgs' own ghostel derivation (manual-packages/ghostel), which
# builds the module from source so the Elisp's `ghostel--minimum-module-version'
# check always matches.  Takes the whole `emacsPackages' set (rather than the
# individual deps) so it stays auto-importable by `pkgs.callPackage' AND can be
# called by apps/emacs
# with that Emacs's own overlaid scope (one magit/transient/evil, not a duplicate).
{
  lib,
  fetchFromGitHub,
  emacsPackages,
  stdenv,
  zig_0_15,
  emacs,
  xcbuild,
  # nixpkgs' Darwin SDK: xcbuild alone lacks an SDK, so libghostty's build.zig
  # fails `findNative' with `error.DarwinSdkNotFound'.  apple-sdk provides the
  # macOS SDK (and sets DEVELOPER_DIR/SDKROOT).  No-op on Linux.  (This folds in
  # what apps/emacs/ghostel.nix used to do out-of-tree.)
  apple-sdk ? null,
}:

let
  inherit (emacsPackages) melpaBuild;
  zig = zig_0_15;

  pname = "ghostel";
  version = "0.44.0";

  src = fetchFromGitHub {
    owner = "dakra";
    repo = "ghostel";
    rev = "v${version}";
    hash = "sha256-vRGZoQtjsL42ga07fOfEjccKRidAhqgwHBoKs++62Ls=";
  };

  libExt = stdenv.hostPlatform.extensions.sharedLibrary;

  # Native (Zig) module.  Built from the SAME `src' as the Elisp so the version
  # sidecar (`ghostel-module.version', written by build.zig) always satisfies the
  # loader's `ghostel--minimum-module-version' check.
  module = stdenv.mkDerivation (finalAttrs: {
    pname = "${pname}-module";
    inherit version src;

    deps = zig.fetchDeps {
      inherit (finalAttrs) src pname version;
      fetchAll = true;
      # Vendored Zig dependency set; refreshed alongside `src' by ./update.sh.
      hash = "sha256-yrVgiofdmVjTGJ+PGPGRCc8gb/JcEca1uAzIoPgHHqU=";
    };

    nativeBuildInputs = [ zig ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ xcbuild ];

    buildInputs = lib.optional (stdenv.hostPlatform.isDarwin && apple-sdk != null) apple-sdk;

    env.EMACS_INCLUDE_DIR = "${emacs}/include";

    dontSetZigDefaultFlags = true;

    doCheck = true;

    zigCheckFlags = [
      "-Dcpu=baseline"
      # https://github.com/ghostty-org/ghostty/blob/main/PACKAGING.md#build-options
      "-Doptimize=ReleaseFast"
    ];

    zigBuildFlags = finalAttrs.zigCheckFlags;

    postConfigure = ''
      cp -rLT ${finalAttrs.deps} "$ZIG_GLOBAL_CACHE_DIR/p"
      chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
    '';
  });

  # Evil integration.  Its `ghostel' dependency is `ghostel-core' below — the
  # copy built here — NOT `emacsPackages.ghostel', which is what kept it in sync
  # in the first place.  Same `src', so its version tracks core exactly.
  evil-ghostel = melpaBuild {
    pname = "evil-ghostel";
    inherit version src;

    files = ''("extensions/evil-ghostel/evil-ghostel.el")'';

    packageRequires = [
      emacsPackages.evil
      ghostel-core
    ];

    meta = {
      homepage = "https://github.com/dakra/ghostel";
      description = "Evil integration for the ghostel terminal";
      license = lib.licenses.gpl3Plus;
    };
  };

  # ghostel core: the Elisp (MELPA `:defaults' also globs lisp/*.el and drops
  # tests) with the native module + its version sidecar installed in, exactly as
  # nixpkgs does.
  ghostel-core = melpaBuild {
    inherit pname version src;

    files = ''(:defaults "etc" "ghostel-module${libExt}" "ghostel-module.version")'';

    preBuild = ''
      install ${module}/ghostel-module${libExt} ghostel-module${libExt}
      install --mode=444 ${module}/ghostel-module.version ghostel-module.version
    '';

    passthru = {
      inherit module evil-ghostel;
      # Exposed flat (not `module.deps') so `nix-update --custom-dep zigDeps' can
      # find it: nix-update looks up `pkg.<name>.outputHash' as a single attr, so
      # a dotted path like `module.deps' fails.  ./update.sh refreshes this in the
      # same run as `src'.
      zigDeps = module.deps;
    };

    meta = {
      homepage = "https://github.com/dakra/ghostel";
      description = "Terminal emulator powered by libghostty";
      license = lib.licenses.gpl3Plus;
    };
  };
in
ghostel-core
