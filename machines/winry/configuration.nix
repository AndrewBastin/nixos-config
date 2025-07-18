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
  
  # winry runs Determinate Nix, which manages stuff on nix-darwin's behalf
  nix.enable = false;

  environment.systemPackages = [
    nvim
    (pkgs-unstable.callPackage ../../patches/claude-code {})
  ];

  environment.variables.EDITOR = "nvim";

  # Aerospace startup is handled by programs.aerospace.start-at-login in home.nix

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Set wallpaper using LaunchAgent
  launchd.user.agents.setWallpaper = let
    desktoppr = pkgs-unstable.callPackage ../../apps/desktoppr.nix {};
    wallpaper = ./wallpaper.png;
  in {
    serviceConfig = {
      ProgramArguments = [
        "${desktoppr}/bin/desktoppr"
        "${wallpaper}"
      ];
      RunAtLoad = true;
      StandardOutPath = "/tmp/wallpaper-set.log";
      StandardErrorPath = "/tmp/wallpaper-set.log";
    };
  };

  system.configurationRevision = flake.rev or flake.dirtyRev or null;
  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
}
