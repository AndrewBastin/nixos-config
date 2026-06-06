{ callPackage, naersk-input }:

let
  naersk = callPackage ../naersk.nix { inherit naersk-input; };
in
  naersk.buildPackage {
    src = ./.;
  }
