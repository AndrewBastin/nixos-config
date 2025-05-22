# NOTE: This is a nix-darwin configuration module, as opposed to a nixos configuration module
{ flake, nvim, pkgs-unstable, home-manager, ... }: 
{
  users.users.andrew = {
    name = "andrew";
    home = "/Users/andrew";
  };

  imports = [
    home-manager.darwinModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;

      home-manager.users.andrew = import ./home.nix;
    }
  ];
  
  # uwu runs Determinate Nix, which manages stuff on nix-darwin's behalf
  nix.enable = false;

  environment.systemPackages = [
    nvim
    (pkgs-unstable.callPackage ./patches/claude-code {})
  ];

  environment.variables.EDITOR = "nvim";


  system.configurationRevision = flake.rev or flake.dirtyRev or null;
  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
}
