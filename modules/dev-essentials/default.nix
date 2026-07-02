# Dev Essentials Universal Module
#
# Provides essential development tools and shell configuration.
#
# What this module does:
# - Installs core development tools (gh, tig, nodejs, bat, claude-code, amp, codex)
# - Builds and includes custom Neovim configuration via nixvim
# - Configures git with user info and difftastic integration
# - Sets up enhanced shell experience (zsh, fzf, zoxide)
# - Enables direnv for project-specific environments
# - Provides consistent shell aliases and environment variables
# - Manages AI tool skills (Claude Code + Amp) declaratively
# - Manages Claude Code plugins declaratively via shell aliases
#
# Imports: ../kitty (terminal emulator)
#
# Platforms: Home Manager, NixOS, Darwin
#
# Configuration options:
# - dev-essentials.additionalSkills: Extra skill directories to install for AI tools
# - dev-essentials.additionalPlugins: Extra Claude Code plugin directories to load
#
# Key features:
# - Self-contained Neovim built from nixvim input
# - Modern shell tools (fzf fuzzy finder, zoxide smart cd)
# - Development workflow tools (GitHub CLI, git GUI, Node.js)
# - Enhanced terminal experience with syntax highlighting
# - Project environment management via direnv
# - Shared AI skills across Claude Code and Amp
# - Claude Code plugins loaded via shell aliases (--plugin-dir)
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
          Additional skills to install for AI tools (Claude Code, Amp, Codex).
          Each entry can be:
          - A path to a .nix file: resolved via callPackage, must return a path/derivation containing <skill-name>/SKILL.md subdirectories
          - A path to a directory: used directly, should contain <skill-name>/SKILL.md subdirectories
          - A derivation: used directly, should contain <skill-name>/SKILL.md subdirectories
        '';
      };

      additionalCodexSkills = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
        description = ''
          Additional skills to install ONLY for Codex CLI (routed to ~/.agents/skills).
          Use this for skills that depend on codex-specific tools or conventions
          that other agents (Claude Code, Amp) wouldn't be able to use.
          Same entry shape as additionalSkills.
        '';
      };

      additionalPlugins = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
        description = ''
          Additional Claude Code plugins to load via --plugin-dir.
          Each entry can be:
          - A path to a .nix file: resolved via callPackage, must return a plugin directory (containing .claude-plugin/plugin.json)
          - A path to a directory: used directly
          - A derivation: used directly
        '';
      };

      emacs = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install the opt-in, store-baked Emacs (apps/emacs) for this user.
          Exploration tooling; off by default. Installs the `emacs` command.
        '';
      };
    };
  };

  nixos = { pkgs, ... }: {
    programs.zsh.enable = true;
    users.users.andrew.shell = pkgs.zsh;

    # Numtide binary cache — backs llm-agents.nix (claude-code, amp, codex, …)
    # so we pull pre-built binaries instead of rebuilding from source.
    nix.settings = {
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
  };

  # Darwin mirror of the `nixos` numtide cache config above. The Macs run
  # Determinate Nix, so this is routed through the determinate nix-darwin module's
  # `determinateNix.customSettings` (option defined by the module imported in
  # mac-essentials) which writes /etc/nix/nix.custom.conf.
  darwin = { ... }: {
    # Numtide binary cache — backs llm-agents.nix (claude-code, amp, codex, …)
    # so we pull pre-built binaries instead of rebuilding from source.
    determinateNix.customSettings = {
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
  };

  home = { pkgs, pkgs-unstable, inputs, universalConfig ? {}, ... }:
    let
      my_nvim = import ../../apps/nvim.nix {
        pkgs = pkgs-unstable;

        nixvim = inputs.nixvim.legacyPackages."${pkgs.stdenv.system}";
      };

      my_emacs = import ../../apps/emacs {
        pkgs = import inputs.nixpkgs-unstable {
          inherit (pkgs.stdenv.hostPlatform) system;
          overlays = [ inputs.emacs-overlay.overlays.default ];
        };
      };

      llm-agents = inputs.llm-agents.packages."${pkgs.stdenv.system}";

      # TODO: Unpin claude-code when https://github.com/anthropics/claude-code/issues/65989 fix lands.
      # Currently we are pinning it to 2.1.162. Newer releases ship a rendering bug that 
      # has gone unfixed for a while as mentioned in the issue.
      claude-code-pinned =
        (builtins.getFlake "github:numtide/llm-agents.nix/7ddf15a44b60bd5708e76e2b4956978f8486d643")
          .packages."${pkgs.stdenv.hostPlatform.system}".claude-code;

      maniyan = pkgs.callPackage ../../apps/maniyan {
        pi = llm-agents.pi;
      };

      # AI tool skills: combine built-in skill packages with any additional ones from config
      builtinSkills = let
        skillDir = ./ai/skills;
        entries = builtins.readDir skillDir;
        nixFiles = pkgs.lib.filterAttrs (name: type: type == "regular" && pkgs.lib.hasSuffix ".nix" name) entries;
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

      # Codex-only skills: shared skills + a separate codex-only auto-discovery
      # directory + machine-supplied codex-only additions. Routed exclusively
      # to ~/.agents/skills so Claude Code and Amp don't see them.
      builtinCodexSkills = let
        codexSkillDir = ./ai/skills-codex;
        entries = builtins.readDir codexSkillDir;
        nixFiles = pkgs.lib.filterAttrs (name: type: type == "regular" && pkgs.lib.hasSuffix ".nix" name) entries;
      in map (name: codexSkillDir + "/${name}") (builtins.attrNames nixFiles);

      rawAdditionalCodexSkills = universalConfig.dev-essentials.additionalCodexSkills or [];

      allCodexOnlySkillSources = map resolveSkill (builtinCodexSkills ++ rawAdditionalCodexSkills);

      combinedCodexSkills = pkgs.runCommand "combined-codex-skills" {} (
        "mkdir -p $out\n" +
        builtins.concatStringsSep "\n" (map (src: ''
          for skill in ${src}/*/; do
            [ -d "$skill" ] && ln -s "$skill" "$out/$(basename "$skill")"
          done
        '') (allSkillSources ++ allCodexOnlySkillSources)));

      # Claude Code plugins: auto-discover from ./ai/plugins/ and merge with additional
      builtinPlugins = let
        pluginDir = ./ai/plugins;
        entries = builtins.readDir pluginDir;
        nixFiles = pkgs.lib.filterAttrs (name: type: type == "regular" && pkgs.lib.hasSuffix ".nix" name) entries;
      in map (name: pluginDir + "/${name}") (builtins.attrNames nixFiles);

      rawAdditionalPlugins = universalConfig.dev-essentials.additionalPlugins or [];

      resolvePlugin = entry:
        let
          isNixFile = builtins.isPath entry && pkgs.lib.hasSuffix ".nix" (toString entry);
        in
          if isNixFile then pkgs.callPackage entry {}
          else entry;

      allPluginSources = map resolvePlugin (builtinPlugins ++ rawAdditionalPlugins);

      pluginDirFlags = builtins.concatStringsSep " " (map (p: "--plugin-dir ${p}") allPluginSources);

      claudeSettings = {
        skipDangerousModePermissionPrompt = true;
        theme = "dark";
        editorMode = "vim";
        agentPushNotifEnabled = true;

        # Turn off background agents and the `claude agents` agent view.
        disableAgentView = true;

        # Ring the terminal bell on permission prompts and on turn end.
        # Hooks run without a controlling terminal, so we can't write BEL to
        # /dev/tty directly — instead we return it via terminalSequence and
        # Claude Code emits it through its own write path. Kitty
        # (window_alert_on_bell defaults to yes) flips the urgency hint on
        # the OS window, which andrew-shell paints orange on unselected
        # workspaces. BEL travels through SSH TTYs, so this works for remote
        # sessions too. Requires Claude Code v2.1.141+.
        #
        # We use Stop instead of the Notification `idle_prompt` matcher
        # because idle_prompt fires only after a delay; Stop fires the
        # instant Claude yields the turn ("I'm free now").
        #
        # PreToolUse on AskUserQuestion bells the moment Claude raises an
        # interview-style question mid-turn (which does not trigger Stop).
        hooks = let
          ringBell = {
            type = "command";
            command = "printf '%s' '{\"terminalSequence\":\"\\u0007\"}'";
          };
        in {
          Notification = [{
            matcher = "permission_prompt";
            hooks = [ ringBell ];
          }];

          Stop = [{
            hooks = [ ringBell ];
          }];

          PreToolUse = [{
            matcher = "AskUserQuestion";
            hooks = [ ringBell ];
          }];
        };
      };

      claudeSettingsJson = builtins.toJSON claudeSettings;
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

          claude-code-pinned
          llm-agents.amp
          llm-agents.codex

          maniyan
        ] ++ pkgs.lib.optional
          (universalConfig.dev-essentials.emacs or false) my_emacs;

        # Claude Code settings — written to both config dirs (clod uses
        # ~/.claude, migu uses ~/.claude-migu via CLAUDE_CONFIG_DIR).
        # force=true because the existing settings.json is hand-written.
        home.file.".claude/settings.json" = {
          text = claudeSettingsJson;
          force = true;
        };

        home.file.".claude-migu/settings.json" = {
          text = claudeSettingsJson;
          force = true;
        };

        # Place AI skills for both Claude Code and Amp
        home.file.".claude/skills" = {
          source = combinedSkills;
          recursive = true;
        };

        home.file.".claude-migu/skills" = {
          source = combinedSkills;
          recursive = true;
        };

        home.file.".config/agents/skills" = {
          source = combinedSkills;
          recursive = true;
        };

        # Codex CLI looks for skills under ~/.agents/skills (preferred over the
        # legacy ~/.codex/skills location). Same SKILL.md format as Claude Code.
        # Uses combinedCodexSkills so codex-only skills (e.g. superpowers) reach
        # codex without being mounted into Claude Code / Amp's skill paths.
        home.file.".agents/skills" = {
          source = combinedCodexSkills;
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

            # Codex with permission/sandbox bypass, parallel to clod/migu.
            # Skills (including superpowers) are auto-discovered via
            # ~/.agents/skills/ — no marketplace install needed.
            sama = "codex --yolo";
          } // (if allPluginSources != [] then {
            migu = "CLAUDE_CONFIG_DIR=$HOME/.claude-migu claude ${pluginDirFlags} --allow-dangerously-skip-permissions";
            clod = "claude ${pluginDirFlags} --allow-dangerously-skip-permissions";
          } else {
            migu = "CLAUDE_CONFIG_DIR=$HOME/.claude-migu claude --allow-dangerously-skip-permissions";
            clod = "claude --allow-dangerously-skip-permissions";
          });

          syntaxHighlighting.enable = true;

          # Default $EDITOR to nvim, but RESPECT an inherited value rather than
          # overwriting it.  Ghostel terminals (Emacs) set $EDITOR to a blocking
          # emacsclient in the child env before this .zshenv runs (see apps/emacs
          # ghostel.el); with an unconditional `export EDITOR=nvim' that override
          # would be clobbered, so `${EDITOR:-nvim}' lets the Emacs value win
          # inside ghostel while everything else still defaults to nvim.  In
          # envExtra (.zshenv) so it covers non-interactive shells too.
          envExtra = /* sh */ ''
            export EDITOR="''${EDITOR:-nvim}"
          '';
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

          flavors = {
            catppuccin-mocha = pkgs.callPackage ../../packages/yazi-catppuccin-mocha/package.nix {};
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
