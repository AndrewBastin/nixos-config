# muru — pi with our extensions baked in.
#
# All configuration lives in the nix store and arrives as CLI flags, so nothing is
# written to $HOME by us. muru's writable state lives in ~/.muru/ (its own dir, not
# shared with bare pi's ~/.pi/agent/), which keeps `pi install` and `/settings`
# working as escape hatches without either agent stepping on the other.
#
# Uses callPackage convention. Receives `pi` as an override from the caller.
{
  lib,
  writeShellScriptBin,
  runCommand,
  callPackage,
  pi,
}:

let
  # Built-in plugins, auto-discovered from ./plugins/. Each subdirectory holds a
  # default.nix that returns the entry point to pass to pi's -e flag. Adding a
  # built-in plugin is just dropping a folder in there — no other code changes.
  builtinPlugins = let
    pluginDir = ./plugins;
    entries = builtins.readDir pluginDir;
    dirs = lib.filterAttrs (name: type: type == "directory") entries;
  in map (name: import (pluginDir + "/${name}/default.nix") { inherit lib runCommand callPackage pi; })
    (builtins.attrNames dirs);

  pluginFlags = lib.concatMapStringsSep " " (p: "-e ${p}") builtinPlugins;

  # Built-in skills, auto-discovered from ./skills/. Each subdirectory holds a
  # default.nix that returns a store path holding <skill-name>/SKILL.md
  # directories. Adding a built-in skill is just dropping a folder in there — no
  # other code changes.
  #
  # muru's skill set is deliberately independent of the combined set
  # dev-essentials mirrors into ~/.agents/skills for the other agents. Ambient
  # discovery is off (-ns below), so this list is the only thing that grants muru
  # a skill — empty means pi's built-in capabilities only.
  builtinSkills = let
    skillDir = ./skills;
    entries = builtins.readDir skillDir;
    dirs = lib.filterAttrs (name: type: type == "directory") entries;
  in map (name: import (skillDir + "/${name}/default.nix") { inherit lib callPackage; })
    (builtins.attrNames dirs);

  skillFlags = lib.concatMapStringsSep " " (s: "--skill ${s}") builtinSkills;

  # Appended to pi's default system prompt. Empty = pi's default, unchanged.
  # Deliberately a let-binding, not a function argument: muru's prompt is muru's,
  # not something machines override.
  systemPrompt = "";

  systemPromptFlag = lib.optionalString (systemPrompt != "")
    "--append-system-prompt ${lib.escapeShellArg systemPrompt}";

# PI_PACKAGE_DIR, PI_SKIP_VERSION_CHECK=1 and PI_TELEMETRY=0 already come from
# llm-agents' pi wrapper and exec inherits them; only the data dir is ours.
in writeShellScriptBin "muru" ''
  # Give muru its own state dir instead of sharing bare pi's ~/.pi/agent. pi
  # creates it on demand, so no mkdir here. Overridable from the environment for
  # one-off throwaway profiles.
  export PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-$HOME/.muru}"


  # -ns disables pi's ambient skill discovery (~/.agents/skills,
  # ~/.muru/skills, and project-level .pi/skills / .agents/skills). Any --skill
  # path is still additive despite it, so the `skills` list above is the sole
  # source of muru's skills rather than whatever happens to be lying around.
  exec ${pi}/bin/pi -ns ${skillFlags} ${pluginFlags} ${systemPromptFlag} "$@"
''
