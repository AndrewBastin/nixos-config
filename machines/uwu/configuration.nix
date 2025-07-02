# NOTE: This is a nix-darwin configuration module, as opposed to a nixos configuration module
{ flake, nvim, pkgs-unstable, home-manager, inputs, ... }: 
{
  users.users.andrew = {
    name = "andrew";
    home = "/Users/andrew";
  };

  system.primaryUser = "andrew";

  imports = [
    ./homebrew.nix
    ./system-defaults.nix
    home-manager.darwinModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;

      home-manager.extraSpecialArgs = {
        inherit pkgs-unstable;
      };

      home-manager.sharedModules = [
        inputs.mac-app-util.homeManagerModules.default
      ];

      home-manager.users.andrew = import ./home.nix;
    }
  ];
  
  # uwu runs Determinate Nix, which manages stuff on nix-darwin's behalf
  nix.enable = false;

  environment.systemPackages = [
    nvim
    (pkgs-unstable.callPackage ../../patches/claude-code {})
  ];

  environment.variables.EDITOR = "nvim";

  # Custom launchd agent for aerospace startup
  launchd.user.agents.aerospace = {
    command = "open -a AeroSpace";
    serviceConfig = {
      RunAtLoad = true;
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  system.configurationRevision = flake.rev or flake.dirtyRev or null;
  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
}
