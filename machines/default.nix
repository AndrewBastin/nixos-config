{
  uwu = {
    system = "aarch64-darwin";
    stateVersion = 6;
    homeStateVersion = "24.11";

    modules = [ 
      ../modules/dev-essentials
      ../modules/mac-essentials
      ./uwu/modules/homebrew.nix
      ./uwu/modules/system-defaults.nix
      ./uwu/modules/machine-home.nix
    ];

    config = {
      mac-essentials.macUsesDeterminateNix = true;
    };

    darwin = {
      modules = [
        ./uwu/configuration.nix
      ];
    };
  };

  winry = {
    system = "aarch64-darwin";
    stateVersion = 6;
    homeStateVersion = "24.11";

    modules = [ 
      ../modules/dev-essentials
      ../modules/mac-essentials
      ./winry/modules/homebrew.nix
      ./winry/modules/machine-home.nix
    ];

    config = {
      mac-essentials = {
        wallpaper = ./winry/wallpaper.png;
        macUsesDeterminateNix = true;
      };
    };

    darwin = {
      modules = [
        ./winry/configuration.nix
      ];
    };
  };
}
