# Dev Essentials Universal Module
#
# Provides essential development tools and shell configuration.
#
# What this module does:
# - Installs core development tools (gh, tig, nodejs, bat, claude-code)
# - Builds and includes custom Neovim configuration via nixvim
# - Configures git with user info and difftastic integration
# - Sets up enhanced shell experience (zsh, fzf, zoxide)
# - Enables direnv for project-specific environments
# - Provides consistent shell aliases and environment variables
#
# Imports: ../kitty (terminal emulator)
#
# Platforms: Home Manager, Darwin (direnv system-level config)
#
# Key features:
# - Self-contained Neovim built from nixvim input
# - Modern shell tools (fzf fuzzy finder, zoxide smart cd)
# - Development workflow tools (GitHub CLI, git GUI, Node.js)
# - Enhanced terminal experience with syntax highlighting
# - Project environment management via direnv
{
  imports = [
    ../kitty
  ];

  nixos = { pkgs, ... }: {
    programs.zsh.enable = true;
    users.users.andrew.shell = pkgs.zsh;
  };

  home = { pkgs, pkgs-unstable, inputs, ... }:
    let
      my_nvim = import ../../apps/nvim.nix {
        inherit pkgs-unstable;

        nixvim = inputs.nixvim.legacyPackages."${pkgs.stdenv.system}";
      };
    in
      {
        home.packages = with pkgs; [
          tig
          nodejs_20
          bat
          my_nvim
          pkgs-unstable.claude-code
        ];

        programs.gh = {
          enable = true;
          gitCredentialHelper.enable = true;
        };

        programs.git = {
          enable = true;
          userName = "Andrew Bastin";
          userEmail = "andrewbastin.k@gmail.com";

          difftastic.enable = true;
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

          sessionVariables = {
            EDITOR = "nvim";
          };
        };

        programs.zoxide = {
          enable = true;
          enableBashIntegration = true;
          enableZshIntegration = true;
        };

        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
      };
}
