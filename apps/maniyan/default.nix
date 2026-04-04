# Maniyan — pi-based coding agent wrapper.
#
# Uses callPackage convention. Receives `pi` as an override from the caller.
# Internally loads its dependency packages via callPackage.
{
  lib,
  writeShellScriptBin,
  callPackage,
  pi,
}:

let
  # Extensions (loaded via -e)
  pi-vim = callPackage ../../packages/pi-vim/package.nix {};
  pi-btw = callPackage ../../packages/pi-btw/package.nix {};

  extensions = [
    pi-vim
    pi-btw
  ];

  # Skills (loaded via --skill)
  gh-scout-skills = callPackage ../../packages/gh-scout-skills/package.nix {};
  superpowers-plugin = callPackage ../../packages/superpowers-plugin/package.nix {};

  skills = [
    gh-scout-skills
    "${superpowers-plugin}/skills"
    "${pi-btw}/skills"
  ];

  # Prompt templates (loaded via --prompt-template)
  superpowers-prompts = callPackage ../../packages/superpowers-prompts/package.nix {};

  promptTemplates = [
    superpowers-prompts
  ];

  # Config files (immutable, Nix-managed)
  configFiles = ./config;

  # Build flag strings
  extensionFlags = lib.concatMapStringsSep " "
    (ext: "-e ${ext}") extensions;
  skillFlags = lib.concatMapStringsSep " "
    (skill: "--skill ${skill}") skills;
  promptFlags = lib.concatMapStringsSep " "
    (pt: "--prompt-template ${pt}") promptTemplates;

in writeShellScriptBin "maniyan" ''
  MANIYAN_DIR="$HOME/.maniyan"
  mkdir -p "$MANIYAN_DIR"

  # Symlink immutable config from nix store (don't overwrite user files)
  for f in ${configFiles}/*; do
    base=$(basename "$f")
    target="$MANIYAN_DIR/$base"
    # Re-link if pointing to an old store path, or create if missing
    if [ -L "$target" ] || [ ! -e "$target" ]; then
      ln -sf "$f" "$target"
    fi
  done

  export PI_CODING_AGENT_DIR="$MANIYAN_DIR"
  export PI_SKIP_VERSION_CHECK=1
  exec ${pi}/bin/pi ${extensionFlags} ${skillFlags} ${promptFlags} "$@"
''
