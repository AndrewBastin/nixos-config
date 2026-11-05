# A voice typing shortcut, in Hex's portal trigger format (`CTRL+ALT+v`: CTRL/ALT/SHIFT/LOGO
# then an xkb key name), as Hex's own setting and as the Hyprland bind that sends it to Hex.
{ lib }:
let
  order = [ "CTRL" "ALT" "SHIFT" "LOGO" ];
  parts = trigger: lib.splitString "+" trigger;
  # Hex rebuilds the trigger before naming its shortcut, so the bind must too: modifiers in
  # its order, a one-character key lowercase, F-keys uppercase.
  mods = trigger:
    let
      given = lib.init (parts trigger);
      known = map (m: if lib.elem m order then m else throw "voiceTyping: modifier ${m} in \"${trigger}\" isn't one of ${toString order}") given;
    in lib.filter (m: lib.elem m known) order;
  key = trigger:
    let k = lib.last (parts trigger); lower = lib.toLower k;
    in if lib.stringLength k == 1 then lower
      else if builtins.match "f[0-9]+" lower != null then lib.toUpper lower
      else k;
  canonical = trigger: lib.concatStringsSep "+" (mods trigger ++ [ (key trigger) ]);
  hexName = { CTRL = "control"; ALT = "option"; SHIFT = "shift"; LOGO = "command"; };
  hyprName = m: if m == "LOGO" then "SUPER" else m;
in
{
  # `CTRL+ALT+v` → `control+option+v`, the `*_hotkey` setting.
  hexSetting = trigger: lib.concatStringsSep "+" (map (m: hexName.${m}) (mods trigger) ++ [ (key trigger) ]);

  # Hyprland assigns portal shortcuts their keys itself. Hex names each one `<base>-<trigger
  # with + → ->` (its `portal_shortcut_id`), e.g. `dictation-ALT-space`.
  hyprBind = base: trigger:
    "${lib.concatMapStringsSep " " hyprName (mods trigger)}, ${key trigger}, global, anomaly.hex:${base}-${lib.replaceStrings [ "+" ] [ "-" ] (canonical trigger)}";
}
