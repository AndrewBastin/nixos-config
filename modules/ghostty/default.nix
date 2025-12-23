# Ghostty Terminal Universal Module
#
# Configures Ghostty terminal emulator with consistent theming and behavior.
#
# What this module does:
# - Installs and configures Ghostty terminal emulator
# - Uses monospace font from fonts module
# - Applies Builtin Pastel Dark theme
# - Configures macOS-specific titlebar and behavior settings
# - Sets up convenient keybindings for tab management
# - Enables shell integration for bash and zsh
#
# Imports: fonts
#
# Platforms: Home Manager
#
# Configuration options:
# - ghostty.fontSize: Font size for terminal (default: 14)
#
# Key features:
# - Nerd Font support for enhanced terminal experience
# - macOS-optimized settings (titlebar, quit behavior)
# - Shell integration for better command history/navigation
# - Convenient tab management keybindings
{
  options = { lib, ... }: {
    ghostty = {
      fontSize = lib.mkOption {
        type = lib.types.int;
        default = 14;
        description = "Font size for Ghostty terminal";
      };
    };
  };

  imports = [
    ../fonts
  ];

  home = { pkgs, universalConfig ? {}, ... }: 
    let
      fontSize = universalConfig.ghostty.fontSize or 14;
      fontName = universalConfig.fonts.monospace.name;
    in
      {
        programs.ghostty = {
          enable = true;
          settings = {
            font-family = fontName;
            font-size = fontSize;
            
            # Theme - using Builtin Pastel Dark theme
            theme = "Builtin Pastel Dark";
            
            # Cursor settings
            cursor-style = "block";
            cursor-style-blink = false;
            
            # macOS specific settings
            macos-titlebar-style = "hidden";
            macos-option-as-alt = true;
            quit-after-last-window-closed = true;
            
            # Window settings
            window-padding-x = 10;
            window-padding-y = 10;
            window-decoration = false;
            
            # Other settings
            confirm-close-surface = false;
            
            # Keybindings
            keybind = [
              # Tab management
              "ctrl+shift+t=new_tab"
              "cmd+t=new_tab"
              
              # Navigation
              "ctrl+shift+left=previous_tab"
              "ctrl+shift+right=next_tab"
              "cmd+shift+[=previous_tab"
              "cmd+shift+]=next_tab"
              
              # Copy/paste
              "ctrl+shift+c=copy_to_clipboard"
              "ctrl+shift+v=paste_from_clipboard"
              "cmd+c=copy_to_clipboard"
              "cmd+v=paste_from_clipboard"
            ];
          };
          
          
          enableBashIntegration = true;
          enableZshIntegration = true;
        };
      };
}
