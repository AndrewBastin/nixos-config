{ callPackage }:

let
  superpowers = callPackage ../../../../packages/superpowers-plugin/package.nix {};
in
  # Codex's plugin hooks feature (which auto-injects `using-superpowers`
  # at session start on claude-code) is gated behind an in-development
  # codex feature flag. Until that ships, expose the skills directly via
  # codex's skill discovery in ~/.agents/skills/ — the model can still
  # invoke them, just without the aggressive "consult skills first"
  # bootstrap.
  "${superpowers}/skills"
