{ config, pkgs, ... }:

{
  home.username = "andrew";
  home.homeDirectory = "/home/andrew";

  wayland.windowManager.hyprland = {
    enable = true;
    extraConfig = builtins.readFile ./config/hypr/hyprland.conf;
  };

  home.packages = with pkgs; [
    firefox
    neovim
    gh
    nodejs_22
    pnpm_10
    kitty
    cargo
    rustc
    nil
    hyprland
    waybar
    wl-clipboard
    pavucontrol
    brightnessctl
    bemenu
    rofi
    hyprpaper
    fzf
    aria2
    ripgrep
    zip 
    unzip
    zellij
    slack
    nix-output-monitor
    nautilus
    gnome-keyring

    # Flameshot compiled with Wayland support (USE_WAYLAND_GRIM flag)
    (flameshot.override { enableWlrSupport = true; })
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
  };

  programs.git = {
    enable = true;
    userName = "Andrew Bastin";
    userEmail = "andrewbastin.k@gmail.com";
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

  # Configure Waybar (Scripts are split so they can be assigned as executable
  home.file.".config/waybar" = {
    source = ./config/waybar;
  };

  home.file.".config/waybar/scripts" = {
    source = ./config/waybar/scripts;
    recursive = true;
    executable = true;
  };

  # Kitty config
  home.file.".config/kitty/kitty.conf".source = ./config/kitty/kitty.conf;

  # ~/.local/bin
  home.file.".local/bin" = {
    source = ./user-local/bin;
    recursive = true;
    executable = true;
  };

  # npmrc patch to install global NPM packages into a local mutable store
  # NOTE: This means that npm global packages won't be managed by Nix and can be mutable!
  #       But this makes it easier for day to day work.
  home.file.".npmrc".source = ./config/npm/.npmrc;


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
