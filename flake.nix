{
  description = "Andrew's NixOS config flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";

      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, home-manager, ... }@inputs: {

    nixosConfigurations =
      let
        # Modules which are common to all NixOS machines
        commonModules = [
          ./configuration.nix

          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "hm-backup";

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

              modules = [config.hardwareConfiguration] ++ commonModules ++ (config.additionalModules or []);
            };
      in
        nixpkgs.lib.mapAttrs machineMapper (import ./machines);

  };
}

