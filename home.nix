# NOTE: nvim is the custom neovim package passed in via 'extraSpecialArgs'
#       check out its code in apps/nvim.nix
{ pkgs, pkgs-unstable, lib, nvim, ... }:

{
  home.username = "andrew";
  home.homeDirectory = "/home/andrew";

  wayland.windowManager.hyprland = {
    enable = true;
    extraConfig = builtins.readFile ./config/hypr/hyprland.conf;
    plugins = [
      pkgs.hyprlandPlugins.hyprsplit
    ];
  };

  home.packages = with pkgs; [
    # Unstable packages
    pkgs-unstable.claude-code
    pkgs-unstable.qutebrowser

    # Custom Packages
    nvim

    file
    firefox
    google-chrome
    gh
    nodejs_22
    pnpm_10
    cargo
    rustc
    nil
    hyprland
    polkit_gnome
    waybar
    wl-clipboard
    pavucontrol
    brightnessctl
    bemenu
    rofi-wayland
    hyprpaper
    fzf
    aria2
    ripgrep
    zip 
    unzip
    zellij
    slack
    nix-output-monitor
    xfce.thunar
    gnome-keyring
    tig
    devenv
    gscreenshot
  ];

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

  programs.git = {
    enable = true;
    userName = "Andrew Bastin";
    userEmail = "andrewbastin.k@gmail.com";
  };

  programs.kitty = {
    enable = true;
    themeFile = "adwaita_darker";
    font.name = "FiraCode Nerd Font Mono";
    settings.cursor_trail = 1;
    keybindings = {
      "ctrl+shift+t" = "launch --cwd=current --type=tab";
    };
    shellIntegration.enableBashIntegration = true;
  };

  # Set the wallpaper via Hyprpaper
  home.file.".config/hypr/hyprpaper.conf".text =
    ''
      preload = ${./config/wallpaper/wallpaper.png}

      # Leading comma is not a typo
      wallpaper = ,${./config/wallpaper/wallpaper.png}

      # No need for IPC as we are not changing the wallpaper directly anyways
      ipc = false
    '';

  # Hyprlock
  home.file.".config/hypr/hyprlock.conf" = {
    source = ./config/hypr/hyprlock.conf;
  };

  # Configure Waybar (Scripts are split so they can be assigned as executable
  home.file.".config/waybar" = {
    source = ./config/waybar;
  };

  # ~/.local/bin
  home.file.".local/bin" = {
    source = ./user-local/bin;
    recursive = true;
    executable = true;
  };

  # Nixpkgs config
  home.file.".config/nixpkgs/config.nix".text = /* nix */ ''
    {
      # Allows nix-shell etc. to use unfree packages without env variable
      allowUnfree = true;
    }
  '';

  # Fix for file picker becoming too big on the main violet laptop screen
  dconf.settings = {
    "org/gtk/settings/file-chooser" = {
      window-size = lib.hm.gvariant.mkTuple [800 600];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  # Qutebrowser
  # We use catppuccin as a theme and we need to pull its source in
  home.file.".config/qutebrowser/catppuccin" = {
    source = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "qutebrowser";
      rev = "808adc3d7d5be6fc573d6be6e9c888cb96b5d6e6";

      hash = "sha256-FmxrgpFlp+cMUdCx5HHIiLMGWML23p+pfxTKT/X0UME=";
    };

    recursive = true;
  };
  home.file.".config/qutebrowser/config.py".source = ./config/qutebrowser/config.py;

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;

    bashrcExtra = ''
      export PATH=$PATH:$HOME/bin:$HOME/.local/bin:$HOME/.local/npm-packages/bin

      source <(fzf --bash)
    '';
  };

  home.stateVersion = "24.11";
  
  programs.home-manager.enable = true;
}
