{
  getNixOSMachines = pkgs:
    let
      filterFunc = _machineName: machineConfig:
        pkgs.lib.hasAttr "nixos" machineConfig;
    in
      pkgs.lib.filterAttrs filterFunc (import ./machines);


  getDarwinMachines = pkgs:
    let
      filterFunc = _machineName: machineConfig:
        pkgs.lib.hasAttr "darwin" machineConfig;
    in
      pkgs.lib.filterAttrs filterFunc (import ./machines);

  buildNixOSConfigFromMachineDef = { inputs, provideNvimForSystem, pkgs, home-manager }: machineName: machineConfig:
    let
      # Modules which are common to all NixOS machines
      commonModules =
        [
          ./configuration.nix

          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "hm-backup";
        

            home-manager.extraSpecialArgs = {
              nvim = provideNvimForSystem machineConfig.system;
            };

            home-manager.users.andrew = import ./home.nix;

          }
        ];
    in
      pkgs.lib.nixosSystem {
        system = machineConfig.system;

        specialArgs = {
          hostname = machineName;
          inputs = inputs;
        };

        modules = 
          [machineConfig.nixos.hardwareConfiguration]
          ++ commonModules
          ++ (machineConfig.nixos.additionalModules or []);
      };
      
  buildDarwinConfigFromMachineDef = { flake, nix-darwin, provideNvimForSystem }: machineName: machineConfig:
    nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit flake;

        hostname = machineName;
        nvim = provideNvimForSystem machineConfig.system;
      };

      modules = machineConfig.darwin.modules;
    };
}
