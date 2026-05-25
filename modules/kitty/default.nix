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
# - kitty.nvimIntegration: ctrl+click a path:line[:col] reference to open it in
#   nvim at that position (default: true)
#
# Key features:
# - Nerd Font support for enhanced terminal experience
# - macOS-optimized settings (titlebar, quit behavior)
# - Shell integration for better command history/navigation
# - Convenient tab management keybindings
# - Optional nvim integration: ctrl+click file references to jump to line/col
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

      nvimIntegration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to enable the nvim integration: ctrl+click a
          `path:line[:col]` reference anywhere in the terminal to open it in
          nvim at that position (installs the open_in_nvim kitten, its
          open-actions.conf entry, and the ctrl+click mouse_map).
        '';
      };

    };
  };

  imports = [
    ../fonts
  ];

  home = { pkgs, lib, universalConfig ? {}, ... }:
    let
      fontSize = universalConfig.kitty.fontSize or 14;
      fontName = universalConfig.fonts.monospace.name;
      nvimIntegration = universalConfig.kitty.nvimIntegration or true;
    in
      {
        # nvim integration (kitty.nvimIntegration): ctrl+click a `path:line[:col]`
        # reference anywhere in the terminal to open it in nvim at that position.
        # The kitten reads the clicked screen line, then reuses a matching nvim in
        # the same OS window or opens a new window. file:// links opened by other
        # means (e.g. plain left-click on a hyperlink) carry only the path, so the
        # kitten reads the line off-screen.
        xdg.configFile = lib.optionalAttrs nvimIntegration {
          "kitty/open-actions.conf".text = ''
            protocol file
            mime text/*
            action kitten open_in_nvim.py "''${FILE_PATH}"
          '';
          "kitty/open_in_nvim.py".source = ./kittens/open_in_nvim.py;
        };

        programs.kitty = {
          enable = universalConfig.kitty.enable or true;
          themeFile = "adwaita_darker";
          # nvim integration ctrl+click handler (kitty.nvimIntegration). ctrl+left
          # is unbound in kitty's defaults. The kitten parses the path:line[:col]
          # from the clicked screen text, so it works even when the reference is
          # plain text rather than an OSC 8 link; non-references fall back to the
          # default link click. The `press grabbed` discard keeps mouse-grabbing
          # TUIs from also receiving the click.
          extraConfig = lib.optionalString nvimIntegration ''
            mouse_map ctrl+left press grabbed discard_event
            mouse_map ctrl+left release grabbed,ungrabbed kitten open_in_nvim.py
          '';
          font = {
            package = null;
            name = fontName;
            size = fontSize;
          };
          settings = {
            enabled_layouts = "splits";
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
            "alt+shift+h" = "neighboring_window left";
            "alt+shift+j" = "neighboring_window down";
            "alt+shift+k" = "neighboring_window up";
            "alt+shift+l" = "neighboring_window right";
            "alt+enter" = "launch --cwd=current --location=vsplit";
            "ctrl+shift+enter" = "launch --cwd=current --location=hsplit";
            "ctrl+alt+h" = "resize_window narrower";
            "ctrl+alt+l" = "resize_window wider";
            "ctrl+alt+j" = "resize_window shorter";
            "ctrl+alt+k" = "resize_window taller";
            "cmd+t" = "launch --cwd=current --type=tab";
          };
          shellIntegration = {
            enableBashIntegration = true;
            enableZshIntegration = true;
          };
        };
      };
}
