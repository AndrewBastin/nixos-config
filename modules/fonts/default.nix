# Fonts Universal Module
#
# Provides centralized font configuration for the system.
#
# What this module does:
# - Defines monospace font choice used across terminal emulators and UI
# - Defaults to Berkeley Mono patched with Nerd Fonts
# - Provides font package for installation
#
# Imports: None
#
# Platforms: Home Manager
#
# Configuration options:
# - fonts.monospace.name: Font family name (default: "BerkeleyMono Nerd Font Mono")
# - fonts.monospace.package: Font package to install, or null to use default Berkeley Mono
#
# Note: The default uses Berkeley Mono which must be added to the Nix store.
# See apps/berkeley-mono.nix for setup instructions.
#
# To use a different font:
#   fonts.monospace.name = "FiraCode Nerd Font Mono";
#   fonts.monospace.package = pkgs.nerd-fonts.fira-code;
{
  options = { lib, ... }: {
    fonts = {
      monospace = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "BerkeleyMono Nerd Font";
          description = "Monospace font family name";
        };
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = "Font package to install. When null, uses Berkeley Mono from the Nix store.";
        };
      };
    };
  };

  home = { lib, pkgs, universalConfig ? {}, ... }:
    let
      berkeleyMono = pkgs.callPackage ../../apps/berkeley-mono.nix {};
      
      monospaceConfig = universalConfig.fonts.monospace or {};
      useDefaultPackage = monospaceConfig.package or null == null;
      
      fontPackage = 
        if useDefaultPackage then berkeleyMono
        else monospaceConfig.package;
    in
    {
      home.packages = lib.mkIf (fontPackage != null) [ fontPackage ];
    };
}
