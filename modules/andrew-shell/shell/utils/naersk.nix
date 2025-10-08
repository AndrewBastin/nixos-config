# Since all of the utils apps are Rust apps right now, we make use of Naersk
# to build it up and write the derivation easily.
# https://github.com/nix-community/naersk
{ callPackage }:
  
let
  naersk-flake = builtins.getFlake "github:nix-community/naersk/0e72363d0938b0208d6c646d10649164c43f4d64";
in
  callPackage naersk-flake {}
