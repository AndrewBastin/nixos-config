# Evaluates to true, or throws. Run from the repo root:
#   nix eval --impure --expr 'import ./modules/andrew-shell/voice-typing-keys-test.nix { lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib; }'
{ lib }:
let k = import ./voice-typing-keys.nix { inherit lib; };
in
assert k.hexSetting "ALT+space" == "option+space";
assert k.hexSetting "CTRL+ALT+v" == "control+option+v";
assert k.hexSetting "LOGO+SHIFT+d" == "shift+command+d";
assert k.hyprBind "dictation" "ALT+space" == "ALT, space, global, anomaly.hex:dictation-ALT-space";
assert k.hyprBind "paste-last" "CTRL+ALT+v" == "CTRL ALT, v, global, anomaly.hex:paste-last-CTRL-ALT-v";
assert k.hyprBind "dictation" "LOGO+space" == "SUPER, space, global, anomaly.hex:dictation-LOGO-space";
# Hex rebuilds the trigger before naming its shortcut: modifiers as CTRL, ALT, SHIFT, LOGO,
# a single-character key lowercase, F-keys uppercase. The bind must use the same name.
assert k.hyprBind "paste-last" "ALT+CTRL+v" == "CTRL ALT, v, global, anomaly.hex:paste-last-CTRL-ALT-v";
assert k.hyprBind "dictation" "LOGO+SHIFT+f23" == "SHIFT SUPER, F23, global, anomaly.hex:dictation-SHIFT-LOGO-F23";
assert k.hyprBind "dictation" "CTRL+V" == "CTRL, v, global, anomaly.hex:dictation-CTRL-v";
assert !(builtins.tryEval (k.hexSetting "SUPER+space")).success;
true
