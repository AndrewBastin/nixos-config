# Suika: the agent box. Paseo is the control plane — a daemon that supervises
# the agent CLIs dev-essentials already installs (claude-code, codex, pi) and
# serves desktop/mobile/web clients so long-running sessions survive the client
# going away.
{
  nixos = { inputs, pkgs, ... }: {
    imports = [ inputs.paseo.nixosModules.paseo ];

    services.paseo = {
      enable = true;

      # Codex >= 0.148 and Claude Code >= 2.1.257 echo MCP protocol 2026-07-28
      # on post-initialize requests, which the bundled MCP SDK rejects with a
      # 400 — Codex agents then silently run without any Paseo tools. Patch
      # from getpaseo/paseo#4375; drop once that (or #4570) lands upstream.
      package = inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./paseo-mcp-protocol-version.patch ];
      });

      # Running as andrew (not the `paseo` system user) flips
      # inheritUserEnvironment on, which puts the home-manager profile on the
      # daemon's PATH so spawned agents can find claude/codex/git, and points
      # PASEO_HOME at ~/.paseo so they reuse the logins already sitting in
      # ~/.claude and ~/.codex.
      user = "andrew";
      group = "users";

      # Bind everywhere rather than the tailscale IP: tailscale0 has no address
      # yet when the unit starts at boot, so a specific bind loses the race.
      # tailscale0 is the only trusted interface (see modules/tailscale) and
      # openFirewall stays off, so 6767 is reachable from the tailnet only.
      listenAddress = "0.0.0.0";

      # Tailscale already carries the traffic; no reason to hand sessions to
      # the upstream relay at app.paseo.sh.
      relay.enable = false;

      # DNS-rebinding guard. Bare IPs are always allowed, these cover the
      # MagicDNS names.
      hostnames = [ "suika" ".ts.net" ];

      # The web UI ships inside the daemon package but is off by default, so
      # the daemon 404s at / until this is set. Passed as an env var rather
      # than through `settings` for the config.json reason below.
      environment.PASEO_WEB_UI_ENABLED = "true";
    };

    # `settings` is deliberately unset: the module rewrites config.json on every
    # start, which would clobber `paseo daemon set-password`. Set the password
    # once by hand on the box instead.
  };
}
