{
  callPackage
}:

let
  naersk-flake = builtins.getFlake "github:nix-community/naersk/0e72363d0938b0208d6c646d10649164c43f4d64";
  naersk = callPackage naersk-flake {};
in
  naersk.buildPackage {
    src = ./.;
  }
