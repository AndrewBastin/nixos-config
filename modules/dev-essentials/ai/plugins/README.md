# Claude Code Plugins

Plugin packages in this directory are automatically discovered and loaded for Claude Code via `--plugin-dir` flags on the `maniyan` shell alias.

## How it works

Every `.nix` file in this directory is auto-discovered at evaluation time and resolved via `pkgs.callPackage`. Each must return a path or derivation that is a valid Claude Code plugin directory (containing `.claude-plugin/plugin.json` or equivalent manifest).

The resolved plugin paths are injected as `--plugin-dir` flags into the `maniyan` shell alias. The `claude` binary itself is left unwrapped — plugins are exclusive to `maniyan`.

## Adding a built-in plugin

Create a `.nix` file in this directory. No other code changes are needed.

### From the packages directory (recommended)

If the plugin is packaged in `packages/`:

```nix
# my-plugin.nix
{ callPackage }:

callPackage ../../../../packages/my-plugin/package.nix {}
```

Then create the package at `packages/my-plugin/package.nix` following the [packages convention](../../../../packages/README.md).

### From a GitHub repo (inline)

```nix
# my-plugin.nix
{ fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "owner";
    repo = "repo";
    rev = "<commit-sha>";
    hash = "<sri-hash>";
  };
in
  "${src}/path/to/plugin"
```

## Per-machine additional plugins

Machines can add extra plugins via `dev-essentials.additionalPlugins` in their config. Entries follow the same rules — `.nix` files get `callPackage`'d, directories and derivations are used directly.

```nix
# In machines/default.nix
config = {
  dev-essentials.additionalPlugins = [
    ./path/to/extra-plugin.nix
  ];
};
```

## Plugin structure

A Claude Code plugin directory must contain a manifest and one or more components:

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json        # or manifest at .claude-plugin (file)
├── commands/              # optional — slash commands
├── agents/                # optional — custom subagents
├── skills/                # optional — agent skills
├── hooks/                 # optional — event handlers
├── .mcp.json              # optional — MCP server integrations
└── settings.json          # optional — default settings
```

See [Claude Code plugin docs](https://code.claude.com/docs/en/plugins) for the full specification.
