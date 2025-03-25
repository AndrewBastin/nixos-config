{
  description = "Andrew's NixOS config flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixvim, flake-utils, home-manager, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      {
        packages = {
          nvim = import ./apps/nvim.nix {
            nixvim = (import nixvim).legacyPackages."${system}";
          };
        };

        apps = {
          nvim = flake-utils.lib.mkApp { drv = self.packages.${system}.nvim; };
        };
      }
    )
    // {
      nixosConfigurations =
        let
          # Modules which are common to all NixOS machines
          commonModules =
            system: 
              [
                ./configuration.nix

                home-manager.nixosModules.home-manager {
                  home-manager.useGlobalPkgs = true;
                  home-manager.useUserPackages = true;

                  home-manager.backupFileExtension = "hm-backup";
              

                  home-manager.extraSpecialArgs = {
                    nvim = self.packages.${system}.nvim;
                  };

                  home-manager.users.andrew = import ./home.nix;

                }
              ];

          machineMapper =
            name: config:
              nixpkgs.lib.nixosSystem {
                system = config.system;

                specialArgs = {
                  hostname = name;
                  inputs = inputs;
                };

                modules = 
                  [config.hardwareConfiguration]
                  ++ (commonModules config.system)
                  ++ (config.additionalModules or []);
              };
        in
          nixpkgs.lib.mapAttrs machineMapper (import ./machines);
    };
}

