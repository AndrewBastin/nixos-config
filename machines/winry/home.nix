{ pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./hm-modules/aerospace
    (import ./hm-modules/kitty { fontSize = 14; })
  ];

  home.packages = with pkgs; [
    nh
    nix-output-monitor
    pkgs-unstable.numi
    tig
    gh
    nodejs_20
    hidden-bar
    bat
    aria2
  ];

  programs.git = {
    enable = true;
    userName = "Andrew Bastin";
    userEmail = "andrewbastin.k@gmail.com";
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;

    autosuggestion = {
      enable = true;
      strategy = ["completion"];
    };

    shellAliases = {
      # zoxide
      cd = "z";
    };

    syntaxHighlighting.enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  home.stateVersion = "24.11";
}
