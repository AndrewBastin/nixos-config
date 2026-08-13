# muru Skills

Skill packages in this directory are automatically discovered and loaded for muru via `--skill` flags on the `muru` wrapper.

## How it works

Every subdirectory in this directory is auto-discovered at evaluation time. Each must contain a `default.nix` that returns a store path holding one or more `<skill-name>/SKILL.md` subdirectories.

The resolved paths are injected as `--skill` flags into the `muru` wrapper. Because muru runs with ambient skill discovery off (`-ns`), this directory is the *only* thing that grants muru a skill — empty means pi's built-in capabilities only.

## Adding a built-in skill

Create a subdirectory with a `default.nix`. No other code changes are needed.

### From the packages directory (recommended)

If the skill is packaged in `packages/`:

```nix
# my-skill/default.nix
{ callPackage }:

callPackage ../../../packages/my-skill/package.nix {}
```

Then create the package at `packages/my-skill/package.nix` following the [packages convention](../../../packages/README.md).

### From a GitHub repo

If the repo has a `skills/` directory with `<skill-name>/SKILL.md` subdirectories:

```nix
# my-skill/default.nix
{ fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "owner";
    repo = "repo";
    rev = "<commit-sha>";
    hash = "<sri-hash>";
  };
in
  "${src}/skills"
```

Get the hash with:
```sh
nix-prefetch-url --unpack "https://github.com/owner/repo/archive/<commit-sha>.tar.gz"
# Then convert: nix hash convert --hash-algo sha256 --to sri <hash>
```

### From a local directory

If you have skill files checked into this repo elsewhere:

```nix
# my-skill/default.nix
{ }:
  ./path/to/skills
```

## Skill file format

Pi follows the [Agent Skills standard](https://agentskills.io) — YAML frontmatter with markdown instructions:

```markdown
---
name: my-skill
description: What this skill does and when to use it
---

Instructions for the AI agent...
```

See [pi's skills docs](https://github.com/mariozechner/pi/blob/main/docs/skills.md) for the full specification.
