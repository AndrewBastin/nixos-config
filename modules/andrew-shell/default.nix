{
  options = { lib, ... }: {
    andrew-shell = {
      monitorRules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ", preferred, auto, 1" ];
        description = "Sets the rules for how monitors should be laid out. Follows https://wiki.hypr.land/Configuring/Monitors/";
      };

      wallpaper = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Sets the wallpaper. If set to null (default) it will render a blank black background";
      };

      use-unstable-hyprland = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "If enabled, uses hyprland (and hyprland plugins) provided by nixpkgs-unstable, else uses the defined nixpkgs one";
      };
    };
  };

  nixos = { pkgs, pkgs-unstable, universalConfig ? {}, ... }: {
    programs.hyprland = let
      hyprlandPkgs = if universalConfig.andrew-shell.use-unstable-hyprland then pkgs-unstable else pkgs;
    in 
      {
        enable = true;
        package = hyprlandPkgs.hyprland;
        portalPackage = hyprlandPkgs.xdg-desktop-portal-hyprland;
      };

    # We use ly as the display manager
    services.displayManager.ly = {
      enable = true;
      settings = {
        session_log = ".local/state/ly-session.log";
        hide_version_string = true;
      };
    };

    # We need upower daemon for battery info
    services.upower.enable = true;

    # used by Thunar and Ristretto for thumbnail generation
    services.tumbler.enable = true;

    environment.systemPackages = with pkgs; [
      blueman         # Bluetooth management
      swaynotificationcenter
    ];



    # Stuff related to GPG Agent
    programs.mtr.enable = true;

    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    # Hint to Electron apps to use Wayland
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };

  imports = [
    ../fonts
  ];

  home = { pkgs, pkgs-unstable, lib, inputs, universalConfig ? {}, ... }: 
    let
      fontName = universalConfig.fonts.monospace.name;
    in
    {
    imports = [
      inputs.zen-browser.homeModules.beta

      ./shell
      (import ./lock.nix { fontFamily = fontName; })
    ];

    # They need to be present here so they show up in the app opening view
    home.packages = with pkgs; [
      xfce.thunar         # File Manager
      xfce.ristretto      # Image viewer

      pavucontrol         # Volume and Audio Control

      kitty
      wl-clipboard        # Needed for copy pasting to work on various apps

      rofi
      rofimoji

      (
        pass-wayland.withExtensions (exts: with exts; [
          pass-otp
          pass-update
        ])
      )
      rofi-pass-wayland
    ];

    programs.zen-browser.enable = true;

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "Adwaita-dark";
        };
      };

    home.pointerCursor = {
      gtk.enable = true;
      size = 24;
      package = pkgs.vanilla-dmz;
      name = "DMZ-Black";
    };

    gtk = {
      enable = true;

      iconTheme = {
        package = pkgs.adwaita-icon-theme;
        name = "Adwaita";
      };

      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
      };
    };

    qt = {
      enable = true;
      platformTheme.name = "adwaita";
      style.name = "adwaita-dark";
    };

    services.hyprpaper = {
      enable = universalConfig.andrew-shell.wallpaper != null;
      settings = {
       preload = "${universalConfig.andrew-shell.wallpaper}";
       wallpaper = ",${universalConfig.andrew-shell.wallpaper}";
      };
    };

    # We use Pass as the keyring exposed via pass-secret-service
    services.pass-secret-service.enable = true;


    wayland.windowManager.hyprland = {
      enable = true;

      # Setting this to null will make it so the packages gets sourced from the NixOS module
      package = null;
      portalPackage = null;

      plugins = let
        hyprlandPkgs = if universalConfig.andrew-shell.use-unstable-hyprland then pkgs-unstable else pkgs;
      in
        with hyprlandPkgs.hyprlandPlugins; [
          hyprsplit
        ];

      settings = {
        monitor = universalConfig.andrew-shell.monitorRules or [ ", preferred, auto, 1" ];

        exec-once = [
          "${lib.getExe pkgs.hyprpaper} & ${lib.getExe pkgs.swaynotificationcenter}"
        ];

        plugin = {
          hyprsplit = {
            num_workspaces = 10;
          };
        };

        general = {
          gaps_in = 0;
          gaps_out = 0;

          border_size = 1;

          "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
          "col.inactive_border" = "rgba(595959aa)";

          resize_on_border = false;

          allow_tearing = false;

          layout = "dwindle";
        };

        decoration = {
          rounding = 10;

          active_opacity = 1.0;
          inactive_opacity = 1.0;

          shadow = {
            enabled = true;
            range = 4;
            render_power = 3;
            color = "rgba(1a1a1aee)";
          };

          blur = {
            enabled = true;
            size = 3;
            passes = 1;

            vibrancy = 0.1696;
          };
        };

        animations = {
          enabled = true;

          bezier = [
            "easeOutQuint,0.23,1,0.32,1"
            "easeInOutCubic,0.65,0.05,0.36,1"
            "linear,0,0,1,1"
            "almostLinear,0.5,0.5,0.75,1.0"
            "quick,0.15,0,0.1,1"
          ];

          animation = [
            "global, 1, 10, default"
            "border, 1, 5.39, easeOutQuint"
            "windows, 1, 4.79, easeOutQuint"
            "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
            "windowsOut, 1, 1.49, linear, popin 87%"
            "fadeIn, 1, 1.73, almostLinear"
            "fadeOut, 1, 1.46, almostLinear"
            "fade, 1, 3.03, quick"
            "layers, 1, 3.81, easeOutQuint"
            "layersIn, 1, 4, easeOutQuint, fade"
            "layersOut, 1, 1.5, linear, fade"
            "fadeLayersIn, 1, 1.79, almostLinear"
            "fadeLayersOut, 1, 1.39, almostLinear"
            "workspaces, 1, 1.94, almostLinear, fade"
            "workspacesIn, 1, 1.21, almostLinear, fade"
            "workspacesOut, 1, 1.94, almostLinear, fade"
          ];
        };

        # "Smart gaps" / "No gaps when only"
        workspace = [
          "w[tv1], gapsout:0, gapsin:0"
          "f[1], gapsout:0, gapsin:0"
        ];

        windowrulev2 = [
          # "Smart gaps" / "No gaps when only"
          "bordersize 0, floating:0, onworkspace:w[tv1]"
          "rounding 0, floating:0, onworkspace:w[tv1]"
          "bordersize 0, floating:0, onworkspace:f[1]"
          "rounding 0, floating:0, onworkspace:f[1]"

          # Ignore maximize requests from apps
          "suppressevent maximize, class:.*"

          
          # Fix some dragging issues with XWayland
          "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
        ];

        # https://wiki.hyprland.org/Configuring/Dwindle-Layout/
        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };

        # https://wiki.hyprland.org/Configuring/Master-Layout/
        master = {
          new_status = "master";
        };

        misc = {
          force_default_wallpaper = 0;
          disable_hyprland_logo = true;
        };

        "$mod" = "SUPER";

        bind = let
          quickmenu = pkgs.callPackage ./quickmenu.nix { fontFamily = fontName; };
          app_runner = /* sh */ ''
            ${lib.getExe pkgs.rofi} -show combi -modes combi -combi-modes "window,drun,run" -show-icons
          '';
          screenshot = /* sh */ ''
            ${lib.getExe pkgs.hyprshot} -m region --clipboard-only
          '';

          password-manager = /* sh */ ''
            ${lib.getExe pkgs.rofi-pass-wayland}
          '';

          emoji-picker = /* sh */ ''
            ${lib.getExe pkgs.rofimoji}
          '';
        in
          [
            # TODO: Power shortcuts
            "$mod, T, exec, ${lib.getExe pkgs.kitty}"
            "$mod, Q, killactive"
            "$mod, M, exec, ${quickmenu.power}"
            "$mod, E, exec, ${lib.getExe pkgs.xfce.thunar}"

            # TODO: This should be Zen by default
            "$mod, F, exec, zen"

            "$mod, B, exec, ${quickmenu.bluetooth}"

            "$mod, V, togglefloating"
            "$mod, R, exec, ${app_runner}"
            "$mod, P, pseudo"
            "$mod, J, togglesplit"

            "$mod SHIFT, left, movewindow, mon:l"
            "$mod SHIFT, right, movewindow, mon:r"

            
            "$mod, 1, split:workspace, 1"
            "$mod, 2, split:workspace, 2"
            "$mod, 3, split:workspace, 3"
            "$mod, 4, split:workspace, 4"
            "$mod, 5, split:workspace, 5"
            "$mod, 6, split:workspace, 6"
            "$mod, 7, split:workspace, 7"
            "$mod, 8, split:workspace, 8"
            "$mod, 9, split:workspace, 9"
            "$mod, 0, split:workspace, 10"

            "$mod SHIFT, 1, split:movetoworkspace, 1"
            "$mod SHIFT, 2, split:movetoworkspace, 2"
            "$mod SHIFT, 3, split:movetoworkspace, 3"
            "$mod SHIFT, 4, split:movetoworkspace, 4"
            "$mod SHIFT, 5, split:movetoworkspace, 5"
            "$mod SHIFT, 6, split:movetoworkspace, 6"
            "$mod SHIFT, 7, split:movetoworkspace, 7"
            "$mod SHIFT, 8, split:movetoworkspace, 8"
            "$mod SHIFT, 9, split:movetoworkspace, 9"
            "$mod SHIFT, 0, split:movetoworkspace, 10"

            # Moves the windows in invalid workspaces into the existing one
            # useful when unplugging monitors
            "$mod SHIFT, G, split:grabroguewindows"

            # Swaps workspaces between monitors
            # "$mod SHIFT, D, split:swapactiveworkspaces, current +1"

            "$mod SHIFT, P, exec, ${screenshot}"
            "$mod SHIFT, C, exec, ${password-manager}"
            "$mod SHIFT, E, exec, ${emoji-picker}"

            # Example special workspace (scratchpad)
            "$mod, S, togglespecialworkspace, magic"
            "$mod SHIFT, S, movetoworkspace, special:magic"

            # Scroll through existing workspaces with mainMod + scroll
            "$mod, left, movefocus, l"
            "$mod, right, movefocus, r"
          ];

        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];

        bindel = let
          vol_increase = "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
          vol_decrease = "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";

          toggle_mute = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          toggle_mic_mute = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";

          brightness_increase = "${lib.getExe pkgs.brightnessctl} s 10%+";
          brightness_decrease = "${lib.getExe pkgs.brightnessctl} s 10%-";
        in
          [
            ",XF86AudioRaiseVolume, exec, ${vol_increase}"
            ",XF86AudioLowerVolume, exec, ${vol_decrease}"
            ",XF86AudioMute, exec, ${toggle_mute}"
            ",XF86AudioMicMute, exec, ${toggle_mic_mute}"
            ",XF86MonBrightnessUp, exec, ${brightness_increase}"
            ",XF86MonBrightnessDown, exec, ${brightness_decrease}"
          ];

        bindl = let
          playerctl = lib.getExe pkgs.playerctl;

          play_next = "${playerctl} next";
          play_pause = "${playerctl} play-pause";
          play_prev = "${playerctl} previous";
        in
          [
            ", XF86AudioNext, exec, ${play_next}"
            ", XF86AudioPause, exec, ${play_pause}"
            ", XF86AudioPlay, exec, ${play_pause}"
            ", XF86AudioPrev, exec, ${play_prev}"

            # Additional binds for keyboards that don't have media control buttons
            "$mod, bracketright, exec, ${play_prev}"
            "$mod, bracketleft, exec, ${play_next}"
            "$mod SHIFT, bracketright, exec, ${play_pause}"
          ];

        input = {
          touchpad = {
            natural_scroll = true;
          };
        };
        
        xwayland = {
          force_zero_scaling = true;
        };
      };
    };
  };
}
