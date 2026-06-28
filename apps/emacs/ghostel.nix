# Transform that makes nixpkgs' `ghostel` Emacs package build its native (Zig)
# module from source on Darwin too, keeping the native binary in lockstep with
# the Elisp version on every platform.
#
# The loader in ghostel.el calls `ghostel--module-version` (a function exported
# BY the compiled module) and refuses to run when it is older than the Elisp's
# `ghostel--minimum-module-version` ("module version is older than required
# version").  Because nixpkgs builds the module from the SAME source rev as the
# Elisp, a from-source build always satisfies that check — so the fix for the
# recurring breakage on emacs-overlay bumps is simply to build from source on
# every platform.
#
#   * Linux: nixpkgs already builds the module from source, so this is a no-op.
#
#   * Darwin: nixpkgs' module derivation wires up only `xcbuild`, not an SDK, so
#     libghostty's `build.zig` fails in `findNative` with
#     `error.DarwinSdkNotFound`.  Adding `apple-sdk` (the modern nixpkgs Darwin
#     SDK package — it provides the macOS SDK and sets DEVELOPER_DIR/SDKROOT, the
#     missing piece `xcbuild` alone can't supply) to the module's build inputs
#     lets the from-source build find the SDK.  We then install that module the
#     same way upstream's `preBuild` does.
#
# NOTE: the Darwin path is unverified from a Linux host (Nix can't build a Darwin
# derivation here) — validate it by building on a Mac (winry/uwu).  If the SDK
# still isn't found, fall back to a prebuilt release asset.
#
# Apply over the whole Emacs package scope (see ./default.nix) so dependents like
# `evil-ghostel`, whose `ghostel` dependency resolves to this same package, pick
# up the result too.
{ lib
, stdenv
, apple-sdk ? null
}:

let
  libExt = stdenv.hostPlatform.extensions.sharedLibrary;
in
# `elisp` is nixpkgs' `ghostel` package; return it transformed (Darwin) or
# untouched (Linux).
elisp:

if !stdenv.hostPlatform.isDarwin then
  # Linux: nixpkgs' from-source module already matches the Elisp version.
  elisp
else
  # Darwin: rebuild the native module with the macOS SDK available, then install
  # it exactly the way upstream's `preBuild` does (the package's `files`
  # directive picks `ghostel-module${libExt}` and its sidecar up from the build
  # dir).  Replacing `preBuild` drops the reference to the original SDK-less
  # `module`, so only this SDK-augmented build runs.
  let
    module = elisp.module.overrideAttrs (o: {
      buildInputs = (o.buildInputs or [ ])
        ++ lib.optional (apple-sdk != null) apple-sdk;
    });
  in
  elisp.overrideAttrs (_: {
    preBuild = ''
      install ${module}/lib/libghostel-module${libExt} ghostel-module${libExt}
      install --mode=444 ${module}/ghostel-module.version ghostel-module.version
    '';
  })
