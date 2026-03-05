# Since all of the utils apps are Rust apps right now, we make use of Naersk
# to build it up and write the derivation easily.
# https://github.com/nix-community/naersk
{ callPackage, naersk-input }:

callPackage naersk-input {}
