# Buzz Agents Module
#
# Runs headless Buzz agents on a NixOS host so they are shared by every user of
# the workspace instead of living inside one person's Buzz Desktop. Each agent
# gets its own Unix user, home directory (its "nest") and systemd service that
# runs the `buzz-acp` harness driving `claude-agent-acp`.
#
# Secrets (the agent's Nostr private key, the owner attestation and optionally
# an Anthropic API key) are NOT in this repo. They live in one EnvironmentFile
# per agent under `buzz-agents.secretsDir`; see ./README.md for the format.
# A service whose secrets file is missing simply stays inactive.
{
  options = { lib, ... }: {
    buzz-agents = {
      relayUrl = lib.mkOption {
        type = lib.types.str;
        default = "wss://chibi.communities.buzz.xyz";
        description = "Buzz relay the agents connect to.";
      };

      ownerPubkey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Hex pubkey of the agents' owner (used for the owner-only respond gate).";
      };

      respondTo = lib.mkOption {
        type = lib.types.enum [ "owner-only" "allowlist" "anyone" "nobody" ];
        default = "allowlist";
        description = ''
          Which authors' mentions the harness forwards to the agent.
          `allowlist` = owner plus `respondToAllowlist`; `anyone` = every channel member.
        '';
      };

      respondToAllowlist = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Hex pubkeys allowed to drive the agents in `allowlist` mode (owner is implicit).";
      };

      model = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "claude-fable-5-1[1m]";
        description = "Default model ID applied to every agent session (per-agent `model` overrides).";
      };

      homeBase = lib.mkOption {
        type = lib.types.str;
        default = "/srv/agents";
        description = "Parent directory of the per-agent home directories.";
      };

      secretsDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/buzz-agents";
        description = "Directory holding one `<agent>.env` EnvironmentFile per agent (root-only).";
      };

      agents = lib.mkOption {
        default = { };
        description = "Agents to run, keyed by a short lowercase name (becomes the `buzz-<name>` user).";
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            displayName = lib.mkOption {
              type = lib.types.str;
              description = "Name shown in Buzz (must match the agent's profile).";
            };

            systemPrompt = lib.mkOption {
              type = lib.types.str;
              description = "Persona instructions passed to the harness as the agent's system prompt.";
            };

            model = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Model ID for this agent; falls back to `buzz-agents.model`.";
            };

            parallelism = lib.mkOption {
              type = lib.types.int;
              default = 4;
              description = "Number of parallel ACP worker subprocesses (BUZZ_ACP_AGENTS).";
            };

            extraEnvironment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Extra non-secret environment variables for the harness.";
            };
          };
        });
      };
    };
  };

  nixos = { pkgs, lib, inputs, universalConfig ? { }, ... }:
    let
      cfg = universalConfig.buzz-agents or { };
      agents = cfg.agents or { };

      llm-agents = inputs.llm-agents.packages.${pkgs.stdenv.system};
      buzz = pkgs.callPackage ../../packages/buzz/package.nix { };

      userOf = name: "buzz-${name}";
      homeOf = name: "${cfg.homeBase}/${name}";
      secretsFileOf = name: "${cfg.secretsDir}/${name}.env";

      # Mirrors the nest layout Buzz Desktop creates for local agents.
      nestDirs = [ "RESEARCH" "PLANS" "GUIDES" "WORK_LOGS" "OUTBOX" "REPOS" ".scratch" ];

      mkUser = name: agent: lib.nameValuePair (userOf name) {
        isNormalUser = true;
        group = "buzz-agents";
        home = homeOf name;
        createHome = true;
        description = "Buzz agent ${agent.displayName}";
      };

      mkService = name: agent:
        let
          model = if agent.model != null then agent.model else cfg.model;
          promptFile = pkgs.writeText "buzz-agent-${name}-system-prompt.md" agent.systemPrompt;
        in
        lib.nameValuePair "buzz-agent-${name}" {
          description = "Buzz agent ${agent.displayName} (buzz-acp harness)";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" "tailscaled.service" ];

          # Stay quiet until the operator has dropped the secrets file in place.
          unitConfig.ConditionPathExists = secretsFileOf name;

          # Tools the agent (Claude Code under claude-agent-acp) gets on its PATH.
          path = [
            buzz
            llm-agents.claude-code
            llm-agents.claude-agent-acp
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.gawk
            pkgs.git
            pkgs.openssh
            pkgs.curl
            pkgs.jq
            pkgs.ripgrep
            pkgs.nodejs
          ];

          environment = {
            HOME = homeOf name;
            BUZZ_RELAY_URL = cfg.relayUrl;
            BUZZ_ACP_AGENT_OWNER = cfg.ownerPubkey;
            BUZZ_ACP_AGENT_COMMAND = "${llm-agents.claude-agent-acp}/bin/claude-agent-acp";
            BUZZ_ACP_AGENT_ARGS = "";
            CLAUDE_CODE_EXECUTABLE = "${llm-agents.claude-code}/bin/claude";
            BUZZ_ACP_DISPLAY_NAME = agent.displayName;
            BUZZ_ACP_SESSION_TITLE = agent.displayName;
            BUZZ_ACP_SYSTEM_PROMPT_FILE = "${promptFile}";
            BUZZ_ACP_RESPOND_TO = cfg.respondTo;
            BUZZ_ACP_RESPOND_TO_ALLOWLIST = lib.concatStringsSep "," cfg.respondToAllowlist;
            BUZZ_ACP_AGENTS = toString agent.parallelism;
            BUZZ_ACP_DEDUP = "queue";
            BUZZ_ACP_MULTIPLE_EVENT_HANDLING = "steer";
            BUZZ_ACP_SESSION_POLICY = "channel";
            BUZZ_ACP_RELAY_OBSERVER = "true";
          }
          // lib.optionalAttrs (model != null) { BUZZ_ACP_MODEL = model; }
          // agent.extraEnvironment;

          serviceConfig = {
            User = userOf name;
            Group = "buzz-agents";
            WorkingDirectory = homeOf name;
            # BUZZ_PRIVATE_KEY, BUZZ_AUTH_TAG and optionally ANTHROPIC_API_KEY.
            EnvironmentFile = secretsFileOf name;
            ExecStart = "${buzz}/bin/buzz-acp";
            Restart = "on-failure";
            RestartSec = "10s";
            KillMode = "mixed";
            TimeoutStopSec = 30;
          };
        };
    in
    lib.mkIf (agents != { }) {
      users.groups.buzz-agents = { };
      users.users = lib.mapAttrs' mkUser agents;

      systemd.services = lib.mapAttrs' mkService agents;

      systemd.tmpfiles.rules =
        [ "d ${cfg.secretsDir} 0750 root root -" ]
        ++ lib.concatLists (lib.mapAttrsToList (name: _:
          [ "d ${homeOf name} 0750 ${userOf name} buzz-agents -" ]
          ++ map (d: "d ${homeOf name}/${d} 0750 ${userOf name} buzz-agents -") nestDirs
        ) agents);

      # Make the Buzz CLI available to humans on the box too (debugging, `buzz mem`).
      environment.systemPackages = [ buzz ];
    };
}
