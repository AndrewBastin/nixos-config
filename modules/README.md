# Universal Modules

This directory contains universal modules that work across NixOS, nix-darwin, and Home Manager configurations. Universal modules provide a unified way to configure software and system settings that can be shared between different platforms.

## How Universal Modules Work

Universal modules are structured Nix files that can contain platform-specific configurations:

```nix
{
  # Optional: Import other universal modules
  imports = [
    ./other-module
  ];

  # Optional: Configuration options (using nixpkgs lib.modules system)
  options = { lib, ... }: {
    moduleName = {
      someOption = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Description of what this option does";
      };
    };
  };

  # Optional: Home Manager configuration
  home = { pkgs, universalConfig ? {}, ... }: {
    # Home Manager configuration here
    programs.example.enable = true;
  };

  # Optional: nix-darwin configuration  
  darwin = { pkgs, universalConfig ? {}, ... }: {
    # macOS system configuration here
    system.defaults.dock.autohide = true;
  };

  # Optional: NixOS configuration
  nixos = { pkgs, universalConfig ? {}, ... }: {
    # NixOS system configuration here
    services.example.enable = true;
  };
}
```

## Key Features

### 1. Cross-Platform Compatibility
Universal modules automatically extract the relevant configuration for each platform:
- `home` section applies to Home Manager
- `darwin` section applies to nix-darwin (macOS)  
- `nixos` section applies to NixOS

### 2. Configuration Options
Modules can define configuration options using the nixpkgs lib.modules system. These options can be set in machine definitions and accessed via `universalConfig` parameter.

### 3. Module Imports
Universal modules can import other universal modules, enabling composition and code reuse.

### 4. Automatic Integration
Universal modules are processed by `lib.nix` and automatically integrated into the appropriate system configurations.

## Using Universal Modules

### In Machine Definitions

Add universal modules to your machine definition in `machines/default.nix`:

```nix
{
  myMachine = {
    system = "aarch64-darwin";
    
    modules = [
      ../modules/dev-essentials    # Shared universal module
      ../modules/mac-essentials    # macOS-specific universal module
      ./myMachine/modules/custom   # Machine-specific universal module
    ];
    
    config = {
      # Configure module options
      moduleName.someOption = true;
    };
  };
}
```

### Platform-Specific Parameters

Universal modules receive these parameters:
- `pkgs`: Standard nixpkgs
- `pkgs-unstable`: Unstable nixpkgs (in home/darwin sections)
- `universalConfig`: Evaluated configuration options from all modules
- `inputs`: Flake inputs
- Standard platform parameters (config, lib, etc.)

## Available Modules

- **aerospace/**: Window manager configuration for macOS
- **dev-essentials/**: Essential development tools (imports kitty)
- **kitty/**: Terminal emulator configuration
- **mac-essentials/**: macOS system defaults and utilities (imports aerospace)
- **macos-defaults/**: Additional macOS system preferences

## Machine-Specific Modules

You can create machine-specific universal modules in `machines/{machine}/modules/`:
- `homebrew.nix`: Machine-specific Homebrew packages
- `machine-home.nix`: Machine-specific home packages
- `system-defaults.nix`: Machine-specific system preferences

These follow the same universal module structure but are only loaded for specific machines.
