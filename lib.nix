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

  buildNixOSConfigFromMachineDef = { inputs, provideNvimForSystem, pkgs, nixpkgs-unstable, home-manager }: machineName: machineConfig:
    let
      pkgs-unstable = import nixpkgs-unstable {
        system = machineConfig.system; 
        config.allowUnfree = true;
      };

      # Modules which are common to all NixOS machines
      commonModules =
        [
          ./configuration.nix
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "hm-backup";
        

            home-manager.extraSpecialArgs = {
              inherit pkgs-unstable inputs;

              nvim = provideNvimForSystem machineConfig.system;
            };

            home-manager.users.andrew = import ./home.nix;

          }
        ];
    in
      pkgs.lib.nixosSystem {
        system = machineConfig.system;

        specialArgs = {
          inherit pkgs-unstable;

          hostname = machineName;
          inputs = inputs;
        };

        modules = 
          [machineConfig.nixos.hardwareConfiguration]
          ++ commonModules
          ++ (machineConfig.nixos.additionalModules or []);
      };
      
  buildDarwinConfigFromMachineDef = { flake, nixpkgs-unstable, home-manager, nix-darwin, provideNvimForSystem, inputs }: machineName: machineConfig:
    nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit flake home-manager inputs;

        pkgs-unstable = import nixpkgs-unstable {
          system = machineConfig.system; 
          config.allowUnfree = true;
        };

        hostname = machineName;
        nvim = provideNvimForSystem machineConfig.system;
      };

      # mac-app-util is assumed as a default for now
      modules = [inputs.mac-app-util.darwinModules.default] ++ machineConfig.darwin.modules;
    };
}
