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
        pkgs = pkgs-unstable;

        nixvim = inputs.nixvim.legacyPackages."${pkgs.stdenv.system}";
      };

      llm-agents = inputs.llm-agents.packages."${pkgs.stdenv.system}";
    in
      {
        home.packages = with pkgs; [
          tig
          nodejs_24
          bat
          my_nvim
          jq
          lazygit
          ripgrep
          zip
          unzip

          # used by jujutsu for change tracking
          watchman

          llm-agents.claude-code
          llm-agents.amp
        ];

        programs.gh = {
          enable = true;
          gitCredentialHelper.enable = true;
        };

        programs.git = {
          enable = true;

          settings = {
            user = {
              name = "Andrew Bastin";
              email = "andrewbastin.k@gmail.com";
            };

            init.defaultBranch = "main";
          };
        };

        programs.difftastic = {
          enable = true;
          git.enable = true; # Use difftastic as the diff program for `git diff` and friends
        };

        programs.fzf = {
          enable = true;
          enableZshIntegration = true;
          enableBashIntegration = true;
        };

        programs.jujutsu = {
          enable = true;
          package = pkgs-unstable.jujutsu;
          settings = {
            user = {
              email = "andrewbastin.k@gmail.com";
              name = "Andrew Bastin";
            };

            ui.default-command = "log";

            # Use watchman for auto snapshotting
            fsmonitor = {
              backend = "watchman";

              # Use watchman hooks for snapshotting
              watchman.register-snapshot-trigger = true;
            };
          };
        };

        programs.jjui = {
          enable = true;
          package = pkgs-unstable.jjui;
        };

        programs.zsh = {
          enable = true;
          enableCompletion = true;

          autosuggestion = {
            enable = true;
            strategy = ["completion"];
          };

          # A fix for the issue with Claude Code's Bash Tool failing when using cd: https://github.com/anthropics/claude-code/issues/2407
          initContent = /* sh */ ''
            if [[ "$CLAUDECODE" != "1" ]]; then
              eval "$(zoxide init --cmd cd zsh)"
            fi

            # Ctrl+e to edit current command in $EDITOR
            autoload -Uz edit-command-line
            zle -N edit-command-line
            bindkey '^e' edit-command-line
          '';

          shellAliases = {
            # Commented out to enable the custom fix for Claude Code. See `programs.zsh.initContent` definition in this file for more info
            # zoxide
            # cd = "z";

            lg = "lazygit";
            maniyan = "claude --allow-dangerously-skip-permissions";
          };

          syntaxHighlighting.enable = true;

          sessionVariables = {
            EDITOR = "nvim";
          };
        };

        # Really good completions!
        programs.carapace = {
          enable = true;
          enableZshIntegration = true;
        };

        programs.zoxide = {
          enable = true;
          enableBashIntegration = true;

          # Commented out to enable the custom fix for Claude Code. See `programs.zsh.initContent` definition in this file for more info
          # enableZshIntegration = true;
        };

        programs.yazi = {
          enable = true;

          shellWrapperName = "y";
          
          enableBashIntegration = true;
          enableZshIntegration = true;

          flavors =
            let
              flavorsRepo = pkgs.fetchFromGitHub {
                owner = "yazi-rs";
                repo = "flavors";
                rev = "3edeb49597e1080621a9b0b50d9f0a938b8f62bb";
                hash = "sha256-twgXHeIj52EfpMpLrhxjYmwaPnIYah3Zk/gqCNTb2SQ=";
              };
            in
              {
                catppuccin-mocha = "${flavorsRepo}/catppuccin-mocha.yazi";
              };

          theme.flavor = 
            let
              theme = "catppuccin-mocha";
            in 
              {
                dark = theme;
                light = theme;
              };

        };

        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
        };

        programs.tmux = {
          enable = true;
          keyMode = "vi";
          focusEvents = true;
          mouse = true;
          baseIndex = 1;
          extraConfig = ''
            set -g status-style bg=black,fg=white
            set -g renumber-windows on
            set -g set-titles on
            set -g window-status-format '#I:#{=20:pane_title}'
            set -g window-status-style fg=colour240
            set -g window-status-current-format '#I:#{=20:pane_title}'
            set -g window-status-current-style fg=white
            set -g status-left ""
            set -g status-right ""
          '';
        };
      };
}
