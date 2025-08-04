# Kitty Terminal Universal Module
#
# Configures Kitty terminal emulator with consistent theming and behavior.
#
# What this module does:
# - Installs and configures Kitty terminal emulator
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

  home = { pkgs, universalConfig ? {}, ... }: 
    let
      fontSize = universalConfig.kitty.fontSize or 14;
    in
      {
        programs.kitty = {
          enable = universalConfig.kitty.enable or true;
          themeFile = "adwaita_darker";
          font = {
            package = pkgs.nerd-fonts.fira-code;
            name = "FiraCode Nerd Font Mono";
            size = fontSize;
          };
          settings = {
            cursor_trail = 1;
            macos_titlebar_color = "background";
            macos_quit_when_last_window_closed = "yes";
            macos_show_window_title_in = "window";
          };
          keybindings = {
            "ctrl+shift+t" = "launch --cwd=current --type=tab";
            "cmd+t" = "launch --cwd=current --type=tab";
          };
          shellIntegration = {
            enableBashIntegration = true;
            enableZshIntegration = true;
          };
        };
      };
}
