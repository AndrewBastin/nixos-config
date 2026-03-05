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
# - Manages AI tool skills (Claude Code + Amp) declaratively
#
# Imports: ../kitty (terminal emulator)
#
# Platforms: Home Manager, NixOS, Darwin
#
# Configuration options:
# - dev-essentials.additionalSkills: Extra skill directories to install for AI tools
#
# Key features:
# - Self-contained Neovim built from nixvim input
# - Modern shell tools (fzf fuzzy finder, zoxide smart cd)
# - Development workflow tools (GitHub CLI, git GUI, Node.js)
# - Enhanced terminal experience with syntax highlighting
# - Project environment management via direnv
# - Shared AI skills across Claude Code and Amp
{
  imports = [
    ../kitty
  ];

  options = { lib, ... }: {
    dev-essentials = {
      additionalSkills = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
        description = ''
          Additional skills to install for AI tools (Claude Code, Amp).
          Each entry can be:
          - A path to a .nix file: resolved via callPackage, must return a path/derivation containing <skill-name>/SKILL.md subdirectories
          - A path to a directory: used directly, should contain <skill-name>/SKILL.md subdirectories
          - A derivation: used directly, should contain <skill-name>/SKILL.md subdirectories
        '';
      };
    };
  };

  nixos = { pkgs, ... }: {
    programs.zsh.enable = true;
    users.users.andrew.shell = pkgs.zsh;
  };

  home = { pkgs, pkgs-unstable, inputs, universalConfig ? {}, ... }:
    let
      my_nvim = import ../../apps/nvim.nix {
        pkgs = pkgs-unstable;

        nixvim = inputs.nixvim.legacyPackages."${pkgs.stdenv.system}";
      };

      llm-agents = inputs.llm-agents.packages."${pkgs.stdenv.system}";

      # AI tool skills: combine built-in skill packages with any additional ones from config
      builtinSkills = let
        skillDir = ./ai/skills;
        entries = builtins.readDir skillDir;
        nixFiles = pkgs.lib.filterAttrs (_: type: type == "regular") entries;
      in map (name: skillDir + "/${name}") (builtins.attrNames nixFiles);

      rawAdditionalSkills = universalConfig.dev-essentials.additionalSkills or [];

      # Resolve each skill entry: .nix files get callPackage'd, everything else used directly
      resolveSkill = entry:
        let
          isNixFile = builtins.isPath entry && pkgs.lib.hasSuffix ".nix" (toString entry);
        in
          if isNixFile then pkgs.callPackage entry {}
          else entry;

      allSkillSources = map resolveSkill (builtinSkills ++ rawAdditionalSkills);

      combinedSkills = pkgs.runCommand "combined-ai-skills" {} (
        "mkdir -p $out\n" +
        builtins.concatStringsSep "\n" (map (src: ''
          for skill in ${src}/*/; do
            [ -d "$skill" ] && ln -s "$skill" "$out/$(basename "$skill")"
          done
        '') allSkillSources));
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

        # Place AI skills for both Claude Code and Amp
        home.file.".claude/skills" = {
          source = combinedSkills;
          recursive = true;
        };

        home.file.".config/agents/skills" = {
          source = combinedSkills;
          recursive = true;
        };

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
