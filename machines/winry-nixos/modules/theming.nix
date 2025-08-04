# Theming Universal Module
#
# Configures GTK and QT theming for consistent dark mode experience across applications.
#
# What this module does:
# - Sets up GTK 3/4 themes with Adwaita dark theme
# - Configures QT themes to match GTK using qt5ct/qt6ct
# - Sets Papirus-Dark icon theme for visual consistency
# - Configures cursor theme and size
# - Sets up font configuration
# - Enables dark mode preferences system-wide
#
# Imports: None
#
# Platforms: Home Manager (Linux only, as GTK/QT theming is primarily for Linux)
#
# Configuration options:
# - theming.enable: Enable theming configuration (default: true)
# - theming.cursorSize: Cursor size in pixels (default: 24)
#
# Key features:
# - Consistent dark theme across GTK and QT applications
# - Papirus icon theme for modern look
# - Proper QT/GTK integration via qt5ct
# - System-wide dark mode preferences
{
  options = { lib, ... }: {
    theming = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GTK/QT theming configuration";
      };
      
      cursorSize = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Cursor size in pixels";
      };
    };
  };

  home = { pkgs, lib, universalConfig ? {}, ... }: 
    let
      cfg = universalConfig.theming or {};
      enabled = cfg.enable or true;
      cursorSize = cfg.cursorSize or 24;
    in
      lib.mkIf enabled {
        # GTK theming
        gtk = {
          enable = true;
          
          theme = {
            name = "Adwaita-dark";
            package = pkgs.gnome-themes-extra;
          };
          
          iconTheme = {
            name = "Papirus-Dark";
            package = pkgs.papirus-icon-theme;
          };
          
          gtk3.extraConfig = {
            gtk-application-prefer-dark-theme = 1;
          };
          
          gtk3.extraCss = ''
            .window-frame {
              box-shadow: 0 0 0 0;
              margin: 0;
            }
            window decoration {
              margin: 0;
              padding: 0;
              border: none;
            }
          '';
          
          gtk4.extraConfig = {
            gtk-application-prefer-dark-theme = 1;
          };
          
          gtk4.extraCss = ''
            .background {
              margin: 0;
              padding: 0;
              box-shadow: 0 0 0 0;
            }
          '';
        };

        # QT theming
        qt = {
          enable = true;
          platformTheme.name = "qtct";
          style = {
            name = "adwaita-dark";
            package = pkgs.adwaita-qt;
          };
        };

        # Set cursor theme
        home.pointerCursor = {
          gtk.enable = true;
          name = "Adwaita";
          package = pkgs.adwaita-icon-theme;
          size = cursorSize;
        };

        # Font configuration
        fonts.fontconfig.enable = true;
        
        # Set dark theme preference via dconf (for GNOME/GTK apps)
        # NOTE: Disabled as dconf service is not available on this system
        # dconf.settings = {
        #   "org/gnome/desktop/interface" = {
        #     color-scheme = "prefer-dark";
        #     gtk-theme = "Adwaita-dark";
        #     icon-theme = "Papirus-Dark";
        #   };
        # };

        # Environment variables for QT
        home.sessionVariables = {
          QT_QPA_PLATFORMTHEME = "qt5ct";
        };

        # Ensure qt5ct is installed for QT configuration
        home.packages = with pkgs; [
          libsForQt5.qt5ct
          libsForQt5.qtstyleplugin-kvantum
        ];
      };
}