# Kitty Terminal Universal Module
#
# Configures Kitty terminal emulator with consistent theming and behavior.
#
# What this module does:
# - Installs and configures Kitty terminal emulator
# - Uses monospace font from fonts module
# - Applies Adwaita Darker theme for consistent dark mode
# - Configures macOS-specific titlebar and behavior settings
# - Sets up convenient keybindings for tab management
# - Enables shell integration for bash and zsh
#
# Imports: fonts
#
# Platforms: Home Manager
#
# Configuration options:
# - kitty.fontSize: Font size for terminal (default: 14)
#
# Key features:
# - Nerd Font support for enhanced terminal experience
# - macOS-optimized settings (titlebar, quit behavior)
# - Shell integration for better command history/navigation
# - Convenient tab management keybindings
{
  options = { lib, ... }: {
    kitty = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable kitty";
      };

      fontSize = lib.mkOption {
        type = lib.types.int;
        default = 14;
        description = "Font size for Kitty terminal";
      };

    };
  };

  imports = [
    ../fonts
  ];

  home = { pkgs, universalConfig ? {}, ... }: 
    let
      fontSize = universalConfig.kitty.fontSize or 14;
      fontName = universalConfig.fonts.monospace.name;
    in
      {
        programs.kitty = {
          enable = universalConfig.kitty.enable or true;
          themeFile = "adwaita_darker";
          font = {
            package = null;
            name = fontName;
            size = fontSize;
          };
          settings = {
            cursor_trail = 1;
            macos_titlebar_color = "background";
            macos_quit_when_last_window_closed = "yes";
            macos_show_window_title_in = "window";
          };
          keybindings = {
            "ctrl+shift+n" = "launch --cwd=current --type=os-window";
            "ctrl+shift+t" = "launch --cwd=current --type=tab";
            "ctrl+shift+h" = "move_window left";
            "ctrl+shift+j" = "move_window down";
            "ctrl+shift+k" = "move_window up";
            "ctrl+shift+l" = "move_window right";
            "alt+enter" = "launch --cwd=current --location=vsplit";
            "ctrl+shift+enter" = "launch --cwd=current --location=hsplit";
            "cmd+t" = "launch --cwd=current --type=tab";
          };
          shellIntegration = {
            enableBashIntegration = true;
            enableZshIntegration = true;
          };
        };
      };
}
