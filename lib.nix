rec {
  # Process universal modules with new module system
  processUniversalModulesWithConfig = pkgs: modulePaths: machineConfig:
    let
      # Recursively collect all module paths including imports
      collectAllModulePaths = paths: 
        let
          # Import modules to check for imports
          modules = map (path: import path) paths;
          
          # Extract import paths from modules that have them
          importPaths = builtins.concatLists (map (mod: 
            if builtins.hasAttr "imports" mod 
            then mod.imports 
            else []
          ) modules);
          
          # Recursively collect imports
          allImportPaths = if importPaths != [] 
            then collectAllModulePaths importPaths 
            else [];
            
          # Combine and deduplicate
          allPaths = paths ++ allImportPaths;
        in
          # Remove duplicates by converting to set and back
          builtins.attrValues (builtins.listToAttrs (map (p: { name = toString p; value = p; }) allPaths));
      
      # Get all module paths including transitive imports
      allModulePaths = if modulePaths != []
        then collectAllModulePaths modulePaths
        else [];
      
      # Import all universal modules
      universalModules = map (path: import path) allModulePaths;
      
      # Create proper NixOS-style modules that can be evaluated
      nixModules = map (universalModule: { config, lib, pkgs, ... }: 
        # Only add options if the universal module has them
        if builtins.hasAttr "options" universalModule 
        then {
          options = universalModule.options { inherit config lib pkgs; };
          config = {};
        }
        else {
          # Module has no options, just empty config
          config = {};
        }
      ) universalModules;
      
      # Evaluate the modules with machine config to get resolved options
      evaluated = pkgs.lib.evalModules {
        modules = nixModules ++ [
          # Pass machine config as module (if it exists)
          { config = machineConfig.config or {}; }
        ];
      };
      
      # Return both evaluated config and original modules for platform extraction
      result = {
        evaluatedConfig = evaluated.config;
        universalModules = universalModules;
      };
    in
      result;

  # Extract platform-specific configurations using evaluated config
  extractPlatformConfigs = result: platformType:
    let
      evaluatedConfig = result.evaluatedConfig;
      universalModules = result.universalModules;
      
      # Extract platform configs from universal modules, passing evaluated config
      platformConfigs = builtins.filter (x: x != null) (map (universalModule: 
        if builtins.hasAttr platformType universalModule
        then 
          # Call the platform function with enhanced pkgs that includes universal config
          let
            platformFunc = universalModule.${platformType};
            # Create a module that passes all args to platform function
            platformModule = { config, lib, pkgs, universalConfig ? evaluatedConfig, ... }@args: 
              platformFunc (args // {
                # Ensure universalConfig is available
                universalConfig = universalConfig;
              });
          in platformModule
        else null
      ) universalModules);
    in
      platformConfigs;

  # Legacy functions for backwards compatibility during migration
  processUniversalModules = pkgs: moduleType: universalModules:
    let
      extractModuleType = universalModule:
        if pkgs.lib.hasAttr moduleType universalModule
        then universalModule.${moduleType}
        else null;
      
      filteredModules = builtins.filter (mod: mod != null) 
        (map extractModuleType universalModules);
    in
      filteredModules;

  # Import universal modules by path
  importUniversalModules = pkgs: modulePaths:
    let
      importModule = path: import path;
    in
      if modulePaths != []
      then map importModule modulePaths
      else [];

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

  buildNixOSConfigFromMachineDef = { inputs, pkgs, nixpkgs-unstable, home-manager }: machineName: machineConfig:
    let
      pkgs-unstable = import nixpkgs-unstable {
        system = machineConfig.system; 
        config.allowUnfree = true;
      };

      # Import universal modules (only if specified in machine config)
      modulePaths = machineConfig.modules or [];
      
      # Process universal modules
      processed = if modulePaths != [] then
        processUniversalModulesWithConfig pkgs modulePaths machineConfig
      else
        null;
      
      # Use new module evaluation system if we have module paths
      nixosUniversalModules = if processed != null then
        extractPlatformConfigs processed "nixos"
      else
        # Fallback to legacy system
        let
          universalModules = importUniversalModules pkgs modulePaths;
        in processUniversalModules pkgs "nixos" universalModules;
      
      # Extract home modules from universal modules
      homeUniversalModules = if processed != null then
        extractPlatformConfigs processed "home"
      else
        # Fallback to legacy system
        let
          universalModules = importUniversalModules pkgs modulePaths;
        in processUniversalModules pkgs "home" universalModules;

      # Modules which are common to all NixOS machines
      commonModules =
        [
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "hm-backup";

            home-manager.extraSpecialArgs = {
              inherit pkgs-unstable inputs;
              
              # Pass universal config if we have processed modules
              universalConfig = if processed != null then processed.evaluatedConfig else {};
            };

            home-manager.users.andrew = {
              home.stateVersion = machineConfig.homeStateVersion or "25.05";
            };
            home-manager.sharedModules = homeUniversalModules;

          }
        ];
    in
      pkgs.lib.nixosSystem {
        system = machineConfig.system;

        specialArgs = {
          inherit pkgs-unstable;

          hostname = machineName;
          inputs = inputs;
          
          # Pass universal config if we have processed modules
          universalConfig = if processed != null then processed.evaluatedConfig else {};
        };

        modules = 
          [machineConfig.nixos.hardwareConfiguration]
          ++ commonModules
          ++ (machineConfig.nixos.additionalModules or [])
          ++ nixosUniversalModules
          ++ [
            # Set system state version from machine config
            { system.stateVersion = machineConfig.stateVersion or "25.05"; }
          ];
      };
      
  buildDarwinConfigFromMachineDef = { flake, nixpkgs-unstable, home-manager, nix-darwin, inputs }: machineName: machineConfig:
    let
      pkgs-unstable-for-system = import nixpkgs-unstable {
        system = machineConfig.system; 
        config.allowUnfree = true;
      };

      # Create a temporary pkgs for lib functions
      pkgs-for-lib = import nixpkgs-unstable {
        system = machineConfig.system; 
        config.allowUnfree = true;
      };

      # Import universal modules (only if specified in machine config)
      modulePaths = machineConfig.modules or [];
      
      # Process universal modules
      processed = if modulePaths != [] then
        processUniversalModulesWithConfig pkgs-for-lib modulePaths machineConfig
      else
        null;
      
      # Use new module evaluation system if we have module paths
      darwinUniversalModules = if processed != null then
        extractPlatformConfigs processed "darwin"
      else
        # Fallback to legacy system
        let
          universalModules = importUniversalModules pkgs-for-lib modulePaths;
        in processUniversalModules pkgs-for-lib "darwin" universalModules;
      
      # Extract home modules from universal modules
      homeUniversalModules = if processed != null then
        extractPlatformConfigs processed "home"
      else
        # Fallback to legacy system
        let
          universalModules = importUniversalModules pkgs-for-lib modulePaths;
        in processUniversalModules pkgs-for-lib "home" universalModules;
    in
    nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit flake home-manager inputs;

        pkgs-unstable = pkgs-unstable-for-system;

        hostname = machineName;
        
        # Pass universal config if we have processed modules
        universalConfig = if processed != null then processed.evaluatedConfig else {};
        
        # Pass home modules so machines can include them
        universalHomeModules = homeUniversalModules;
      };

      # mac-app-util is assumed as a default for now
      modules = [inputs.mac-app-util.darwinModules.default] 
        ++ machineConfig.darwin.modules 
        ++ darwinUniversalModules
        ++ [
          # Common Darwin configuration
          {
            # User configuration
            users.users.andrew = {
              name = "andrew";
              home = "/Users/andrew";
            };
            system.primaryUser = "andrew";

            # Home-manager setup
            imports = [
              home-manager.darwinModules.home-manager {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;

                home-manager.extraSpecialArgs = {
                  inherit inputs;
                  pkgs-unstable = pkgs-unstable-for-system;
                  universalConfig = if processed != null then processed.evaluatedConfig else {};
                };

                home-manager.sharedModules = [
                  inputs.mac-app-util.homeManagerModules.default
                ] ++ homeUniversalModules;

                home-manager.users.andrew = { config, pkgs, ... }: {
                  home.stateVersion = machineConfig.homeStateVersion or "24.11";
                };
              }
            ];

            # Set system state version, configuration revision, and host platform from machine config
            system.stateVersion = machineConfig.stateVersion or 6;
            system.configurationRevision = flake.rev or flake.dirtyRev or null;
            nixpkgs.hostPlatform = machineConfig.system;
          }
        ];
    };
}
