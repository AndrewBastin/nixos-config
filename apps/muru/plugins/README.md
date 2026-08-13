# muru Plugins

Plugin packages in this directory are automatically discovered and loaded for muru via `-e` flags on the `muru` wrapper.

## How it works

Every subdirectory in this directory is auto-discovered at evaluation time. Each must contain a `default.nix` that returns the entry point to pass to pi's `-e` flag (a path to an `index.ts`/`index.js`, or a directory whose `package.json` carries a `pi.extensions` manifest).

The resolved entry points are injected as `-e` flags into the `muru` wrapper. Bare `pi` is left unwrapped — plugins are exclusive to muru.

## Skills are loaded separately

muru runs with `-ns` (`--no-skills`), which disables **all** skill loading except explicit `--skill` paths. This has a consequence for plugins that ship skills:

A plugin's `pi.skills` manifest (in its `package.json`) is **not** loaded automatically when the plugin is loaded via `-e`. `-ns` drops the whole "enabled skills" bucket — package skills included — and only `--skill` paths survive.

So if a plugin ships skills, they need a **separate entry in `apps/muru/skills/`** that returns the skills directory, which muru passes via `--skill`.

Example — ponytail is skills-only in muru (its extension is deliberately not loaded):

```nix
# apps/muru/skills/ponytail/default.nix
{ lib, callPackage }:

"${callPackage ../../../../packages/ponytail-plugin/package.nix {}}/skills"
```

which muru passes as `--skill .../ponytail-plugin/skills`. The package's `pi.extensions` manifest is ignored — there is no `apps/muru/plugins/ponytail/` entry, so the extension never loads.

**Rule of thumb:** a plugin folder only covers the extension surface. If the package also declares `pi.skills`, add a sibling folder under `apps/muru/skills/` returning the skills directory — otherwise those skills never load. And the reverse holds too: a package can be skills-only (like ponytail) by having a skill entry and no plugin entry.

## Adding a built-in plugin

Create a subdirectory with a `default.nix`. No other code changes are needed.

### From the packages directory (recommended)

If the plugin is packaged in `packages/`:

```nix
# my-plugin/default.nix
{ callPackage }:

callPackage ../../../packages/my-plugin/package.nix {}
```

Then create the package at `packages/my-plugin/package.nix` following the [packages convention](../../../packages/README.md).

### Authoring a custom extension in the flake

If the plugin is a custom extension written for muru specifically — not something published to npm — you can author it directly in its plugin folder. The folder holds the extension source plus a `default.nix` that packages it into the store and returns the entry point.

A pi extension is just a directory with a `package.json` carrying a `pi.extensions` manifest and one or more entry points. For a single-extension plugin:

```
apps/muru/plugins/my-plugin/
├── default.nix
├── package.json
└── index.ts
```

`package.json` — the `pi.extensions` array lists the entry point(s) pi loads:

```json
{
  "name": "my-plugin",
  "version": "0.1.0",
  "type": "module",
  "pi": {
    "extensions": ["./index.ts"]
  }
}
```

`index.ts` — the extension body. It imports the pi API from the packages pi bundles (`@earendil-works/pi-coding-agent`, `@earendil-works/pi-tui`, …) and registers hooks/commands:

```ts
import { defineExtension } from "@earendil-works/pi-coding-agent";

export default defineExtension(() => {
  // ...
});
```

`default.nix` — packages the local source into the store and returns the entry point to pass to `-e`:

```nix
# my-plugin/default.nix
{ lib, stdenvNoCC, callPackage, pi }:

stdenvNoCC.mkDerivation {
  pname = "my-plugin";
  version = "0.1.0";

  # Package the local source (package.json + index.ts + any helpers) into the
  # store. `./.` is the plugin folder itself.
  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';

  meta = with lib; {
    description = "A custom extension for muru";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
```

Because the `pi.extensions` manifest is present, you can return the whole directory and let pi read the manifest (like pi-ollama-cloud does):

```nix
in "${out}"
```

or, for a single entry point, point straight at it (like pi-vim does):

```nix
in "${out}/index.ts"
```

> **Note:** this is for extensions authored in the flake. Published npm/GitHub plugins should still be packaged in `packages/` (see above) so `just bump`/`nix-update` can track their versions — a hand-written extension has no upstream to bump.

### With muru-specific patching

If the plugin needs to be adapted for muru (e.g. pi-vim's clipboard redirect), keep the patching logic in the plugin's own `default.nix` alongside any supporting files (like a `last-reviewed` version guard). The plugin folder is the right home for anything that is only true about how muru loads that plugin.
