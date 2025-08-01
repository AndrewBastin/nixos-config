# macOS System Defaults configuration for uwu
{
  darwin = { ... }: {
    # System defaults configuration for uwu
    system.defaults = {
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