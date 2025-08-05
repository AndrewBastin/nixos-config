# Mac Essentials Universal Module  
#
# Provides essential macOS system configuration and applications.
#
# What this module does:
# - Installs essential macOS applications (Numi calculator, Hidden Bar)
# - Configures comprehensive macOS system defaults (dock, control center, etc.)
# - Sets up wallpaper management with optional wallpaper setting
# - Manages Determinate Nix integration (disables nix-darwin's nix management)
# - Provides consistent macOS UI/UX settings across machines
#
# Imports: ../aerospace (window manager)
#
# Platforms: Home Manager (apps), Darwin (system defaults, wallpaper, nix config)
#
# Configuration options:
# - mac-essentials.wallpaper: Path to wallpaper image (optional)
# - mac-essentials.macUsesDeterminateNix: Enable Determinate Nix mode (default: false)
#
# Key features:
# - Comprehensive system defaults (dark mode, dock, keyboard, trackpad)
# - Automatic wallpaper setting via LaunchAgent and desktoppr
# - Essential productivity apps for macOS workflow
# - Determinate Nix compatibility mode
{
  imports = [
    ../aerospace
  ];

  options = { lib, ... }: {
    mac-essentials = {
      wallpaper = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to wallpaper image file. If null, no wallpaper will be set.";
      };
      
      macUsesDeterminateNix = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this Mac uses Determinate Nix (disables nix-darwin's nix management)";
      };
    };
  };

  home = { pkgs-unstable, ... }: {
    home.packages = with pkgs-unstable; [
      numi
      hidden-bar
    ];
  };

  darwin = { pkgs-unstable, universalConfig ? {}, ... }: 
    let
      wallpaperPath = universalConfig.mac-essentials.wallpaper or null;
      usesDeterminateNix = universalConfig.mac-essentials.macUsesDeterminateNix or false;
      desktoppr = pkgs-unstable.callPackage ../../apps/desktoppr.nix {};
    in {
    # Disable nix-darwin's nix management if using Determinate Nix
    nix.enable = !usesDeterminateNix;
    
    # Set wallpaper using LaunchAgent (if wallpaper path is provided)
    launchd.user.agents = if wallpaperPath != null then {
      setWallpaper = {
        serviceConfig = {
          ProgramArguments = [
            "${desktoppr}/bin/desktoppr"
            "${wallpaperPath}"
          ];
          RunAtLoad = true;
          StandardOutPath = "/tmp/wallpaper-set.log";
          StandardErrorPath = "/tmp/wallpaper-set.log";
        };
      };
    } else {};

    # macOS System Defaults configuration
    system.defaults = {
      WindowManager = {
        # Click wallpaper to show desktop -> Only in Stage Manager
        EnableStandardClickToShowDesktop = false;
        
        # Tiled windows have margins -> Unchecked
        EnableTiledWindowMargins = false;
      };

      # Dock settings
      dock = {
        autohide = true;
        largesize = 128;
        mineffect = "genie";  # Default minimize effect
        orientation = "bottom";  # Default position
        show-recents = false;  # Commonly desired setting
      };

      # Control Center settings
      controlcenter = {
        BatteryShowPercentage = false;  # Hide battery percentage
        Sound = true;      # Sound control visible
        Bluetooth = true;  # Bluetooth control visible
        AirDrop = false;   # AirDrop hidden
        Display = false;   # Display brightness hidden
        NowPlaying = true; # Now Playing visible
      };

      # Menu bar clock
      menuExtraClock = {
        Show24Hour = false;  # 12-hour format
        ShowAMPM = true;
        ShowDate = 1;  # Show date
        ShowDayOfWeek = true;
        ShowSeconds = false;
      };

      # Global macOS settings
      NSGlobalDomain = {
        # Dark mode
        AppleInterfaceStyle = "Dark";
        
        # Keyboard settings
        ApplePressAndHoldEnabled = false;  # Disable press-and-hold for keys
        InitialKeyRepeat = 25;  # Delay until key repeat starts
        KeyRepeat = 2;  # Fast key repeat rate
        
        # Text input settings
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticDashSubstitutionEnabled = true;
        NSAutomaticPeriodSubstitutionEnabled = true;
        NSAutomaticQuoteSubstitutionEnabled = true;
        
        # UI preferences
        AppleEnableSwipeNavigateWithScrolls = true;
        AppleShowScrollBars = "Automatic";
        
        # Full keyboard navigation
        AppleKeyboardUIMode = 3;
      };

      # Custom user preferences for settings not exposed by nix-darwin
      CustomUserPreferences = {
        NSGlobalDomain = {
          # Show menu bar in fullscreen mode (useful for MacBook Pro with notch)
          AppleMenuBarVisibleInFullscreen = 1;
        };
      };

      # Trackpad settings
      trackpad = {
        Clicking = true;  # Tap to click enabled
        TrackpadRightClick = true;  # Two-finger right-click
      };
    };
  };
}
