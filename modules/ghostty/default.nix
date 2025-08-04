# Ghostty Terminal Universal Module
#
# Configures Ghostty terminal emulator with consistent theming and behavior.
#
# What this module does:
# - Installs and configures Ghostty terminal emulator
# - Sets up FiraCode Nerd Font with configurable font size
# - Applies Adwaita Darker theme for consistent dark mode
# - Configures macOS-specific titlebar and behavior settings
# - Sets up convenient keybindings for tab management
# - Enables shell integration for bash and zsh
#
# Imports: None
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

  home = { pkgs, universalConfig ? {}, ... }: 
    let
      fontSize = universalConfig.ghostty.fontSize or 14;
    in
      {
        programs.ghostty = {
          enable = true;
          settings = {
            # Font configuration
            font-family = "FiraCode Nerd Font Mono";
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
        
        # Ensure the font package is installed
        home.packages = with pkgs; [
          nerd-fonts.fira-code
        ];
      };
}