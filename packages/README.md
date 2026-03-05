# Packages

All non-flake external dependencies are managed as proper nixpkgs-style derivations in this directory. Each subdirectory contains a `package.nix` that is auto-discovered and exposed via `flake.nix` outputs.

## Structure

```
packages/
  <package-name>/
    package.nix       # required — the derivation
    update.sh         # optional — custom update script (for complex cases)
```

Packages are auto-discovered: create a new directory with a `package.nix` and it appears as `packages.<system>.<package-name>` in the flake outputs. No manual registration needed.

## Adding a package

### Tracking a GitHub repo (no releases)

For repos where you want the latest commit from a branch:

```nix
{ lib, stdenvNoCC, fetchFromGitHub, nix-update-script }:

stdenvNoCC.mkDerivation {
  pname = "my-package";
  version = "0-unstable-YYYY-MM-DD"; # commit date of the pinned rev

  src = fetchFromGitHub {
    owner = "owner";
    repo = "repo";
    rev = "<full-commit-sha>";
    hash = "<sri-hash>";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "What this package is";
    homepage = "https://github.com/owner/repo";
    platforms = platforms.all;
  };
}
```

Get the hash:
```sh
nix-prefetch-url --unpack "https://github.com/owner/repo/archive/<commit-sha>.tar.gz"
nix hash convert --hash-algo sha256 --to sri <hash>
```

Get the commit date for the version string:
```sh
gh api repos/owner/repo/commits/<commit-sha> --jq '.commit.committer.date'
```

### Tracking a GitHub repo (with releases)

For repos with tagged releases:

```nix
{ lib, stdenv, fetchurl, nix-update-script }:

stdenv.mkDerivation (finalAttrs: {
  pname = "my-tool";
  version = "1.2.3";

  src = fetchurl {
    url = "https://github.com/owner/repo/releases/download/v${finalAttrs.version}/artifact.tar.gz";
    hash = "<sri-hash>";
  };

  installPhase = ''
    runHook preInstall
    install -D -m755 my-tool $out/bin/my-tool
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "What this tool does";
    homepage = "https://github.com/owner/repo";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
    mainProgram = "my-tool";
  };
})
```

### Proprietary / manual-download software

For software that can't be fetched automatically:

```nix
{ lib, stdenvNoCC, requireFile }:

stdenvNoCC.mkDerivation {
  pname = "proprietary-thing";
  version = "1.0";

  src = requireFile {
    name = "thing.zip";
    sha256 = "<hash>";
    message = ''
      Download from https://example.com and run:
        nix-prefetch-url file:///path/to/thing.zip
    '';
  };

  # ...

  passthru.skipAutoUpdate = true;

  meta.license = lib.licenses.unfree;
}
```

Set `passthru.skipAutoUpdate = true` so `just bump` skips it.

## Versioning convention

Following nixpkgs:

| Situation | Version format | Example |
|---|---|---|
| No upstream releases, tracking a branch | `0-unstable-YYYY-MM-DD` | `0-unstable-2026-02-14` |
| Has releases, tracking beyond latest | `{version}-unstable-YYYY-MM-DD` | `1.2.3-unstable-2026-02-14` |
| Has releases, pinned to a release | `{version}` | `1.2.3` |
| Manual download, no auto-update | Any, with `skipAutoUpdate = true` | `2.004` |

The date must be the **commit date** of the pinned revision, not the date you added the package.

## Updating packages

From the dev shell (`nix develop`):

```sh
just bump          # update all packages + flake inputs
```

Or update a single package:

```sh
nix-update --flake <package-name> --version=branch   # branch-tracking
nix-update --flake <package-name>                      # release-tracking
```

## Migrating to nixpkgs

These packages follow nixpkgs conventions (`package.nix`, `passthru.updateScript`, `meta`). To contribute a package upstream:

1. Copy `packages/<name>/package.nix` to `nixpkgs/pkgs/by-name/<two-letter-prefix>/<name>/package.nix`
2. Replace `nix-update-script { extraArgs = ["--version=branch"]; }` with `unstableGitUpdater { }` (nixpkgs built-in equivalent)
3. Submit a PR to [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs)
