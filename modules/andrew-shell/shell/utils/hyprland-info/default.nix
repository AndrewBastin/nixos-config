{ callPackage }:

let
  naersk = callPackage ../naersk.nix {};
in
  naersk.buildPackage {
    src = ./.;
  }
