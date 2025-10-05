{
  description = "Andrew's NixOS config flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

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
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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


      platformSpecificStuff = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs= nixpkgs.legacyPackages.${system};
          pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
        in
          rec {
            packages = {
              nvim = import ./apps/nvim.nix {
                nixvim = (import nixvim).legacyPackages."${system}";
                pkgs = pkgs-unstable;
              };

              nvim-mini = import ./apps/nvim.nix {
                nixvim = (import nixvim).legacyPackages."${system}";
                noLSP = true;
                noAmp = true;

                pkgs = pkgs-unstable;
              };
            };

            apps = {
              nvim = flake-utils.lib.mkApp {
                drv = self.packages.${system}.nvim;
                name = "nvim";
                exePath = "/bin/nvim";
              };
            };

            devShells.default = pkgs.mkShell {
              packages = (with pkgs; [
                # Required for hyprland-icon-resolver development
                cargo
                rustc

                # Usually used on all of the NixOS/Darwin setups
                nh
              ]) ++ [
                packages.nvim
              ];
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
      platformSpecificStuff // osConfigs;
}

