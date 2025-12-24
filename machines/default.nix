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

  winry-nixos = {
    system = "aarch64-linux";
    stateVersion = "25.11";
    homeStateVersion = "25.11";

    config = {
      ghostty.fontSize = 24;

      dwm = {
        enable = true;
        dpi = 196;
        autoLogin = {
          enable = true;
          user = "andrew";
        };
      };
    };

    modules = [
      ../modules/ghostty
      ../modules/dev-essentials
      ../modules/dwm
      ./winry-nixos/modules/theming.nix
    ];

    nixos = {
      hardwareConfiguration = import ./winry-nixos/modules/hardware-configuration.nix;

      modules = [
        ./winry-nixos/modules/configuration.nix
      ];
    };
  };

  fern = {
    system = "x86_64-linux";
    stateVersion = "25.11";
    homeStateVersion = "25.11";

    config = {
      kitty.fontSize = 11;
      andrew-shell = {
        monitorRules = [
          # Built in monitor - Default configs with a 1.6 scale
          "eDP-1, preferred, auto, 1.6"

          # Dell Monitor on office desk
          "desc:Dell Inc. DELL U2724DE 3SBQ6P3, 2560x1440@120, auto, 1"

          # Lenovo Monitor on office desk
          "desc:Lenovo Group Limited L24i-30 UPB4NZH2, 1920x1080@75, auto, 1"
        ];
        
        wallpaper = ./fern/wallpaper.jpg;
      };
    };

    modules = [
      ../modules/nixos-essentials
      ../modules/dev-essentials
      ../modules/andrew-shell
      ./fern/modules/fern-stuff.nix
    ];

    nixos = {
      hardwareConfiguration = import ./fern/hardware-configuration.nix;

      modules = [
        ./fern/configuration.nix
      ];
    };
  };
}
