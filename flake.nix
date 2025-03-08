{
  description = "Andrew's NixOS config flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";

      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, home-manager, ... }@inputs: {

    # 'violet' is the hostname of the machine
    nixosConfigurations.violet = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-hardware.nixosModules.asus-zephyrus-ga402x-amdgpu
        nixos-hardware.nixosModules.asus-zephyrus-ga402x-nvidia

        ./configuration.nix

        home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          home-manager.backupFileExtension = "hm-backup";

          home-manager.users.andrew = import ./home.nix;
        }
      ];
    };

  };
}

