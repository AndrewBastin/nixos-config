{
  description = "Andrew's NixOS config flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs = { self, nixpkgs, nixvim, nixpkgs-unstable, nix-darwin, flake-utils, home-manager, ... }@inputs:
    let
      lib = import ./lib.nix;


      # Custom apps that I use with special configurations (for example, nvim)
      exportedApps = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
        in
          {
            packages = {
              nvim = import ./apps/nvim.nix {
                inherit pkgs-unstable;

                nixvim = (import nixvim).legacyPackages."${system}";
              };

              nvim-mini = import ./apps/nvim.nix {
                inherit pkgs-unstable;

                nixvim = (import nixvim).legacyPackages."${system}";
                noLSP = true;
              };
            };

            apps = {
              nvim = flake-utils.lib.mkApp {
                drv = self.packages.${system}.nvim;
                name = "nvim";
                exePath = "/bin/nvim";
              };
            };
          }
      );

      # Configurations for NixOS and Darwin machines
      osConfigs = {
        nixosConfigurations =
          let
            mkNixOSConfigFromMachineDef = lib.buildNixOSConfigFromMachineDef {
              inherit inputs home-manager nixpkgs-unstable;

              pkgs = nixpkgs;
            };

          in
            nixpkgs.lib.mapAttrs
              mkNixOSConfigFromMachineDef
              (lib.getNixOSMachines nixpkgs);

        darwinConfigurations =
          let
            mkDarwinConfigFromMachineDef = lib.buildDarwinConfigFromMachineDef {
              inherit nix-darwin nixpkgs-unstable home-manager inputs;
              
              flake = self;
            };
          in
            nixpkgs.lib.mapAttrs
              mkDarwinConfigFromMachineDef
              (lib.getDarwinMachines nixpkgs);
      };
    in
      exportedApps // osConfigs;
}

