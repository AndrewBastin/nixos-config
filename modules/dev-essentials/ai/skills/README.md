# AI Tool Skills

Skill packages in this directory are automatically discovered and installed for both Claude Code (`~/.claude/skills/`) and Amp (`~/.config/agents/skills/`).

## How it works

Every `.nix` file in this directory is auto-discovered at evaluation time and resolved via `pkgs.callPackage`. Each must return a path or derivation containing one or more `<skill-name>/SKILL.md` subdirectories.

## Adding a built-in skill

Create a `.nix` file in this directory. No other code changes are needed.

### From a GitHub repo

If the repo has a `skills/` directory with `<skill-name>/SKILL.md` subdirectories:

```nix
# my-skill.nix
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
# my-skill.nix
{ }:
  ./path/to/skills
```

## Per-machine additional skills

Machines can add extra skills via `dev-essentials.additionalSkills` in their config. Entries follow the same rules — `.nix` files get `callPackage`'d, directories and derivations are used directly.

```nix
# In machines/default.nix
config = {
  dev-essentials.additionalSkills = [
    ./path/to/extra-skill.nix
  ];
};
```

## Skill file format

Both Claude Code and Amp use the same `SKILL.md` format — YAML frontmatter with markdown instructions:

```markdown
---
name: my-skill
description: What this skill does and when to use it
---

Instructions for the AI agent...
```

See [Claude Code skills docs](https://code.claude.com/docs/en/skills.md) and [Amp skills docs](https://ampcode.com/news/agent-skills) for the full specification.
