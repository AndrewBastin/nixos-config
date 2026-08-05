# Syncthing Universal Module
#
# Client half of the Syncthing mesh whose hub is Serie
# (~/serie/containers/syncthing.nix). Declares this machine's peers and
# folders; Nix is the source of truth on both ends, so anything added in the
# WebUI is deleted on the next activation.
#
# Platforms: Home Manager only. home-manager's services.syncthing emits a
# systemd user unit on Linux and a launchd agent on Darwin from the same
# definition, and nix-darwin has no syncthing module at all — so there is
# nothing for the `nixos` or `darwin` sections to do.
#
# Configuration options:
# - syncthing.devices:        peer name -> { id; addresses; } (see below)
# - syncthing.folders:        folder name -> { path; devices; ... }
# - syncthing.ignorePatterns: .stignore contents, applied to every folder
#
# Adding this machine to the mesh is a two-repo handshake, because its
# Syncthing key is generated on first activation rather than declared:
#
#   1. Deploy this config, then read the ID from Syncthing → Actions → Show ID
#      (GUI at http://127.0.0.1:8384).
#   2. Add that ID and this machine's Tailscale IP to `devices` in
#      ~/serie/containers/syncthing.nix, add its name to the `projects`
#      folder's device list, and deploy Serie.
#
# Making step 2 declarative would mean shipping the private key as a secret,
# and this repo has no agenix/sops. Left manual on purpose.
{
  options = { lib, ... }: {
    syncthing = {
      devices = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        example = {
          serie = {
            id = "XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX";
            addresses = [ "tcp://100.109.70.82:22000" ];
          };
        };
        description = ''
          Peers to sync with, passed through to
          home-manager's services.syncthing.settings.devices (which is where
          these attrsets are type-checked — any option it accepts works here).

          `addresses` is effectively required: this mesh runs with every
          discovery mechanism disabled, so a peer with no static address is
          a peer that is never dialed. Use the Tailscale IP, not a MagicDNS
          name — Serie's container resolves only *.serie.

          Do not list the machine itself; Syncthing knows its own identity.
        '';
      };

      folders = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        example = {
          projects = {
            path = "~/Projects";
            devices = [ "serie" ];
          };
        };
        description = ''
          Folders to sync, passed through to home-manager's
          services.syncthing.settings.folders, which type-checks them.

          The attribute name doubles as the folder ID and must match the name
          Serie uses, or the two sides negotiate nothing.

          `path` must be given and must start with `~/`: it is also where the
          generated .stignore lands, which this module writes relative to the
          home directory.
        '';
      };

      ignorePatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "// Machine-local additions, hand-maintained per folder root. Included"
          "// first so a `!path` line there can override the general patterns"
          "// below — Syncthing takes the first matching pattern."
          "//"
          "// The activation script creates this file empty when absent, and that"
          "// is load-bearing: an #include whose target is missing is not skipped,"
          "// it fails the whole ignore file (\"parse error: failed to load"
          "// include file\") and Syncthing then scans the entire tree with zero"
          "// patterns applied."
          "//"
          "// Ignored from syncing on purpose: it is per-machine, and an empty"
          "// copy created here meeting a populated copy from a peer is a"
          "// guaranteed sync conflict. Copy it by hand to share patterns."
          "#include .stignore-local"
          ".stignore-local"
          ""
          "// Build output and dependency trees"
          "node_modules"
          ".pnpm-store"
          "target"
          "dist"
          "build"
          ".next"
          ".turbo"
          "__pycache__"
          "*.pyc"
          ".venv"
          ".tox"
          ".mypy_cache"
          ".pytest_cache"
          ".ruff_cache"
          ".gradle"
          ""
          "// Per-machine tooling state"
          ".direnv"
          "result"
          "result-*"
          ""
          "// A synced index.lock convinces the other machine that a git command is"
          "// already running, and every git operation there fails until it is gone."
          ".git/index.lock"
          ""
          "// Editor and OS noise"
          ".DS_Store"
          "Thumbs.db"
          "*.swp"
        ];
        description = ''
          Ignore patterns written to each folder's .stignore. Syncing build
          output and dependency trees is what makes Syncthing unusable for
          code: hundreds of thousands of small files, endless rescans, and
          half of it is machine-local anyway.

          A pattern without a slash matches at any depth, so `build` and `dist`
          will also hit a source directory that happens to be named that.
          Un-ignore those case by case with a `!some/path/build` line above the
          general pattern.
        '';
      };
    };
  };

  home = { lib, pkgs, universalConfig ? { }, ... }:
    let
      cfg = universalConfig.syncthing or { };
      folders = cfg.folders or { };
      stignore = pkgs.writeText "stignore" (lib.concatLines (cfg.ignorePatterns or [ ]));
    in
    {
      assertions = lib.mapAttrsToList (name: folder: {
        assertion = lib.hasPrefix "~/" (folder.path or "");
        message = "syncthing.folders.${name}.path must be set and start with \"~/\" so the .stignore can be placed relative to the home directory.";
      }) folders;

      services.syncthing = {
        enable = true;

        # This config is the source of truth: peers and folders added from the
        # WebUI are deleted on the next activation, matching how Serie treats
        # its own end of the mesh. Both already default to true — spelled out
        # because it is the whole contract of this module.
        overrideDevices = true;
        overrideFolders = true;

        settings = {
          devices = cfg.devices or { };
          inherit folders;

          # Tailnet-exclusive, mirroring Serie. Every one of these is on by
          # default and would otherwise reach the public internet: announcing
          # this device to discovery.syncthing.net, syncing through community
          # relays (the default listenAddresses include the relay pool), asking
          # the router for a UPnP hole, and STUN probes for QUIC hole-punching.
          # A machine off the tailnet does not sync at all — there is no
          # fallback path.
          options = {
            globalAnnounceEnabled = false;
            localAnnounceEnabled = false;
            relaysEnabled = false;
            natEnabled = false;
            stunServers = [ ];
            listenAddresses = [ "tcp://0.0.0.0:22000" "quic://0.0.0.0:22000" ];

            urAccepted = -1; # decline usage reporting (and its recurring prompt)
            crashReportingEnabled = false;
          };
        };
      };

      # home-manager's syncthing module, unlike the NixOS one, has no
      # ignorePatterns option — it only pushes the folder config over the REST
      # API, and ignores are not part of that object. So write .stignore into
      # the folder root ourselves.
      #
      # Copied rather than placed with home.file, which would symlink it into
      # the store: Syncthing opens files inside a folder with O_NOFOLLOW, so a
      # symlinked .stignore fails to load with ELOOP ("too many levels of
      # symbolic links") and the folder then scans nothing at all. The file is
      # overwritten on every activation, so editing it by hand does not stick.
      # .stignore-local is created before .stignore, never after: .stignore
      # carries an `#include .stignore-local`, and Syncthing treats a missing
      # include target as a fatal parse error that discards every pattern. The
      # `[ -e ]` guard is what keeps it hand-editable — an unconditional install
      # or touch would either truncate it or churn its mtime on every
      # activation.
      home.activation.syncthingIgnores = lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.concatMapStringsSep "\n"
          (folder:
            let root = ''$HOME/${lib.removePrefix "~/" folder.path}''; in
            ''
              [ -e "${root}/.stignore-local" ] || run install -Dm644 /dev/null "${root}/.stignore-local"
              run install -Dm644 ${stignore} "${root}/.stignore"
            '')
          (lib.attrValues folders)
      );
    };
}
