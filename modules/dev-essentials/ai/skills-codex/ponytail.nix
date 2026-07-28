{ callPackage }:

let
  ponytail = callPackage ../../../../packages/ponytail-plugin/package.nix {};
in
  # Same story as superpowers.nix: upstream ships a .codex-plugin manifest that
  # wires up ponytail's SessionStart/UserPromptSubmit hooks, but codex's plugin
  # hooks are still behind an in-development feature flag. Until that ships,
  # expose the skills through codex's ~/.agents/skills discovery — /ponytail and
  # friends still work on demand, just without the always-on ruleset injection
  # Claude Code gets from the plugin.
  #
  # Codex-only (not ai/skills/) so Amp doesn't also pick these up, and so
  # Claude Code sees ponytail exactly once — via the plugin, which already
  # carries the same skills/ directory.
  "${ponytail}/skills"
