# A voice typing shortcut, in Hex's portal trigger format (`CTRL+ALT+v`: CTRL/ALT/SHIFT/LOGO
# then an xkb key name), as Hex's own setting and as the Hyprland bind that sends it to Hex.
{ lib }:
let
  order = [ "CTRL" "ALT" "SHIFT" "LOGO" ];
  parts = trigger: lib.splitString "+" trigger;
  # Modifiers in Hex's order, a one-character key lowercase, F-keys uppercase.
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
  hexName = { CTRL = "control"; ALT = "option"; SHIFT = "shift"; LOGO = "command"; };
  hyprName = m: if m == "LOGO" then "SUPER" else m;
in
{
  # `CTRL+ALT+v` → `control+option+v`, the `*_hotkey` setting.
  hexSetting = trigger: lib.concatStringsSep "+" (map (m: hexName.${m}) (mods trigger) ++ [ (key trigger) ]);

  # Hyprland assigns portal shortcuts their keys itself, so Hex binds them there under the
  # bare name (`portal_shortcut_id` with `desktop_assigns`), e.g. `dictation`.
  hyprBind = base: trigger:
    "${lib.concatMapStringsSep " " hyprName (mods trigger)}, ${key trigger}, global, anomaly.hex:${base}";
}
