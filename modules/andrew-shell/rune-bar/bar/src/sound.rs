//! The speaker item's Sound panel, laid out like macOS's Sound menu: the output volume, then
//! the output devices. Data is PipeWire's (`sources::audio`); actions go through wpctl.

use std::time::{Duration, Instant};

use rune::{Drag, El, Phase, TextStyle, Transition, col, el, row, text};

use crate::sources::{self, AirPods, Sink, SinkKind};
use crate::wifi::{TITLE, badge, muted, panel_box, row_base, section, sep};
use crate::{Bar, Data, LABEL, accent, battery_glyph, c, fg, glyph, hover, spawn, volume_glyph};

/// How long after a slider release it keeps showing the released value: PipeWire's report of
/// the new volume takes a moment, and showing the old one meanwhile makes the knob jump back.
const HOLD: Duration = Duration::from_millis(600);

pub fn toggle_panel(s: &mut Bar) {
    let open = !s.sound_open;
    crate::close_popups(s);
    s.sound_open = open;
}

pub fn close(s: &mut Bar) {
    s.sound_open = false;
    s.airpods_open = false;
    s.vol_hold = None;
}

fn kind_glyph(kind: SinkKind) -> &'static str {
    match kind { SinkKind::Speaker => "\u{f04c3}", SinkKind::Display => "\u{f0379}", SinkKind::Bluetooth => "\u{f02cb}" }
}

/// The volume slider: the speaker glyph (click to mute), then a track whose accent fill ends
/// in the knob. Press anywhere on the track to jump there, or drag.
fn slider(s: &Bar, d: &Data) -> El {
    let a = &d.audio;
    let held = s.vol_hold.filter(|(_, released)| released.is_none_or(|t| t.elapsed() < HOLD)).map(|(v, _)| v);
    let v = held.unwrap_or(a.volume.min(100) as f32 / 100.0);
    let speaker = el().key("mute").w(18.0).center().hit().on_press(|_: &mut Bar| spawn("wpctl", &["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]))
        .child(glyph(volume_glyph(a), 14.0, fg()).key(volume_glyph(a)));
    let fill = row().key("fill").w_frac(v).h_full().radius(3.0).justify_end().items_center()
        .fill(if a.muted { c("#ffffff").alpha(0.35) } else { accent() })
        .child(el().key("knob").size(16.0, 16.0).radius(8.0).mr(-8.0).fill(c("#ffffff")).shadow(1.0, 3.0, c("#000000").alpha(0.4)));
    let track = el().key("track").w_full().h(6.0).radius(3.0).fill(c("#ffffff").alpha(0.18)).child(fill);
    let muted = a.muted;
    // The track is inset by the knob's radius, so its ends are reachable with the knob whole.
    let hitbox = row().key("slider").grow(1.0).h(24.0).px(8.0).items_center().hit().child(track)
        .on_drag(move |s: &mut Bar, g: &mut Drag, tx| {
            let v = ((g.x - 8.0) / (g.w - 16.0)).clamp(0.0, 1.0);
            match g.phase {
                Phase::Down => {
                    g.data = s.vol_hold.map_or(-1.0, |(v, _)| v);
                    // Moving the slider unmutes, as macOS's does.
                    if muted { spawn("wpctl", &["set-mute", "@DEFAULT_AUDIO_SINK@", "0"]); }
                    s.vol_hold = Some((v, None));
                    sources::set_volume(v);
                }
                Phase::Move => { s.vol_hold = Some((v, None)); sources::set_volume(v); }
                Phase::Up => {
                    let v = if g.cancelled() && g.data >= 0.0 { sources::set_volume(g.data); g.data } else { v };
                    s.vol_hold = Some((v, Some(Instant::now())));
                    tx.wake_after(HOLD);
                }
            }
        });
    row_base("volume").child(speaker).child(hitbox)
}

/// An output device; clicking makes it the default. AirPods (`pods`) also show their battery
/// and a chevron that expands their controls (`open`), collapsed by default as on macOS.
fn sink_row(n: &Sink, pods: Option<&AirPods>, open: bool) -> El {
    let id = n.id.to_string();
    let mut label = col().key("label").grow(1.0).gap(1.0)
        .child(text(n.name.clone()).key("name").font(LABEL).color(fg()).truncate());
    // As macOS: the battery on a second line under the name.
    if let Some(pct) = pods.and_then(|p| p.battery) {
        label = label.child(row().key("battery").gap(3.0).items_center()
            .child(glyph(battery_glyph(pct), 11.0, muted()).key(battery_glyph(pct)))
            .child(text(format!("{pct}%")).key("pct").font(TextStyle::new(11.0, 400.0)).color(muted())));
    }
    // A Bluetooth device keeps its row (by address) as its output comes and goes.
    let key = n.mac.as_ref().map_or_else(|| format!("sink-{}", n.id), |m| format!("sink-{m}"));
    let mut r = row_base(&key).child(badge(kind_glyph(n.kind), n.default)).child(label);
    if pods.is_some() {
        let chevron = glyph("\u{f0142}", 14.0, fg()).key("chevron").rotate(if open { std::f32::consts::FRAC_PI_2 } else { 0.0 });
        r = r.child(el().key("expand").size(22.0, 22.0).radius(5.0).center().opacity(0.6).hover(hover()).hit()
            .on_press(|s: &mut Bar| s.airpods_open = !s.airpods_open).child(chevron));
    }
    r.hover(hover()).hit().on_press(move |_: &mut Bar| spawn("wpctl", &["set-default", &id]))
}

/// The noise-control modes in macOS's order: glyph, label, librepods' name.
const MODES: [(&str, &str, &str); 4] = [
    ("\u{f02cb}", "Off", "off"),
    ("\u{f07c5}", "Transparency", "transparency"),
    ("\u{f0674}", "Adaptive", "adaptive"),
    ("\u{f0a45}", "Noise Cancellation", "anc"),
];

/// One choice in a macOS-style list: a check column, the glyph, the label.
fn choice(key: &str, icon: &str, label: &str, on: bool) -> El {
    let check = el().key("check").w(16.0).center();
    row_base(key)
        .child(if on { check.child(glyph("\u{f012c}", 14.0, fg()).key("tick")) } else { check })
        .child(el().key("icon").w(18.0).center().child(glyph(icon, 15.0, fg()).key(icon)))
        .child(text(label.to_owned()).key("label").font(LABEL).color(fg()).grow(1.0))
        .hover(hover()).hit()
}

/// AirPods controls under their output row, laid out like macOS's: Noise Control and
/// Conversation Awareness as checked lists, then taking the audio back from a peer that has it.
fn airpods_controls(p: &AirPods) -> El {
    let mut block = col().key("airpods").w_full().gap(2.0).transition(Transition::opacity())
        .child(sep("noise-sep")).child(section("noise-title", "Noise Control"));
    for &(icon, label, mode) in &MODES {
        block = block.child(choice(mode, icon, label, p.mode == mode)
            .on_press(move |_: &mut Bar| spawn("librepods-ctl", &["mode", mode])));
    }
    block = block.child(sep("ca-sep")).child(section("ca-title", "Conversation Awareness"));
    for (on, icon, label) in [(false, "\u{f0ed4}", "Off"), (true, "\u{f05cb}", "On")] {
        block = block.child(choice(if on { "ca-on" } else { "ca-off" }, icon, label, p.conversational_awareness == on)
            .on_press(move |_: &mut Bar| spawn("librepods-ctl", &["conversational-awareness", if on { "on" } else { "off" }])));
    }
    // Another device of the user's (an iPhone) has the audio: offer to take it back.
    if !p.owns && let Some(peer) = p.peers.iter().find(|x| x.owns) {
        let who = peer.name.clone().unwrap_or_else(|| peer.mac.clone());
        block = block.child(sep("take-sep")).child(row_base("take-back").child(text(format!("Take Audio Back from {who}")).key("label").font(LABEL).color(fg()))
            .hover(hover()).hit().on_press(|_: &mut Bar| spawn("librepods-ctl", &["take-back"])));
    }
    block
}

pub fn panel(s: &Bar, d: &Data) -> Option<El> {
    if !s.sound_open { return None; }
    let mut rows = vec![
        row_base("title").py(6.0).child(text("Sound").key("title").font(TITLE).color(fg())),
        slider(s, d),
        sep("output-sep"),
        section("output-title", "Output"),
    ];
    let pods = d.airpods.as_ref().filter(|p| p.connected);
    // (output, playing from another device). AirPods playing from another device have no output
    // here; list them anyway, as macOS does, and clicking takes the audio back.
    let mut outputs: Vec<(Sink, bool)> = d.audio.sinks.iter().map(|n| (n.clone(), false)).collect();
    if let Some(p) = pods.filter(|p| !d.audio.sinks.iter().any(|n| n.mac.as_deref() == Some(p.mac.as_str()))) {
        outputs.push((Sink {
            id: 0, kind: SinkKind::Bluetooth, default: false, mac: Some(p.mac.clone()),
            name: d.audio.bt_names.get(&p.mac).cloned().unwrap_or_else(|| "AirPods".into()),
        }, true));
    }
    // Headphones first and the built-in speaker last, whichever is in use; by name within each.
    outputs.sort_by_key(|(n, _)| (match n.kind { SinkKind::Bluetooth => 0, SinkKind::Display => 1, SinkKind::Speaker => 2 }, n.name.clone()));
    for (n, away) in &outputs {
        let mine = pods.filter(|p| n.mac.as_deref() == Some(p.mac.as_str()));
        let mut row = sink_row(n, mine, s.airpods_open);
        if *away { row = row.on_press(|_: &mut Bar| spawn("librepods-ctl", &["take-back"])); }
        rows.push(row);
        if let Some(p) = mine.filter(|_| s.airpods_open) { rows.push(airpods_controls(p)); }
    }
    rows.push(sep("settings-sep"));
    rows.push(row_base("settings").py(8.0).child(text("Sound Settings…").key("label").font(LABEL).color(fg()))
        .hover(hover()).hit().on_press(|s: &mut Bar| { close(s); spawn("pavucontrol", &[]); }));
    if voice_typing() {
        rows.push(row_base("voice-typing").py(8.0).child(text("Voice Typing Settings…").key("label").font(LABEL).color(fg()))
            .hover(hover()).hit().on_press(|s: &mut Bar| { close(s); spawn("hex", &["window", "show", "settings"]); }));
    }
    Some(panel_box(s, "sound-panel", rows))
}

/// Whether Hex (voice typing) is installed: Andrew Shell installs it only when it's on.
fn voice_typing() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("PATH").is_some_and(|p| on_path("hex", &p)))
}

/// Whether an executable `name` is in one of `path`'s directories.
fn on_path(name: &str, path: &std::ffi::OsStr) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::env::split_paths(path).any(|dir| std::fs::metadata(dir.join(name)).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0))
}

#[cfg(test)]
mod tests {
    #[test]
    fn finds_a_program_on_path() {
        let dir = std::env::temp_dir().join(format!("andrew-bar-path-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let hex = dir.join("hex");
        std::fs::write(&hex, "").unwrap();
        let path = std::env::join_paths(["/nonexistent".into(), dir.clone()]).unwrap();
        // Present but not executable doesn't count.
        assert!(!super::on_path("hex", &path));
        std::fs::set_permissions(&hex, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        assert!(super::on_path("hex", &path));
        assert!(!super::on_path("nope", &path));
        std::fs::remove_dir_all(dir).unwrap();
    }
}
