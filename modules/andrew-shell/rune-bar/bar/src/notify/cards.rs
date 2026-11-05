//! The pop-up cards: a stack under the bar at the top-right of the focused monitor, in its own
//! overlay that takes the pointer only over cards. Also draws a notification for the bell's list.
//! Ported in part from hokum (https://github.com/anomalyco/hokum, MIT): src/card.rs, src/cards.rs,
//! themes/default.kdl and capsule.kdl (the Capsule look).

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, UNIX_EPOCH};

use rune::{Align, Color, Cx, DisplayTarget, El, OverlayHandle, OverlayInput, OverlayOptions, OverlayPlacement, OverlaySpec, ScreenEdge, TextStyle, Transition, col, el, row, text};

use super::note::{Note, Picture, Timeout};
use crate::{c, fg, vm_mode};

/// GNOME's banner, 34em at its 11pt text (scaled to the bar's 13).
pub const WIDTH: f32 = 440.0;
const GUTTER: f32 = 12.0;
const HEIGHT: f32 = 820.0;
/// The overlay stays up this long after the last card leaves, so it can animate out.
const HIDE_AFTER: Duration = Duration::from_millis(900);

// GNOME Shell's dark theme (gnome-shell-sass: _colors.scss, widgets/_message-list.scss,
// _notifications.scss), its 11pt/9pt/15pt text scaled to the bar's 13/11/18.
pub(crate) const HEADING: TextStyle = TextStyle::new(13.0, 700.0);
pub(crate) const BODY: TextStyle = TextStyle::new(13.0, 400.0);
pub(crate) const CAPTION: TextStyle = TextStyle::new(11.0, 400.0);
pub(crate) const TITLE_2: TextStyle = TextStyle::new(18.0, 800.0);
pub(crate) const TITLE_3: TextStyle = TextStyle::new(18.0, 700.0);

/// The list panel, the same as the bar's other panels.
pub(crate) fn popover() -> Color { c("#1e1e1e") }
/// `.message`, darker than GNOME's (#54545a) by choice.
pub(crate) fn message() -> Color { c("#2e2e32") }
fn message_hover() -> Color { c("#38383c") }
/// The cards stacked under a collapsed group: `:second-in-stack`, `:lower-in-stack`.
pub(crate) fn second_in_stack() -> Color { c("#29292c") }
pub(crate) fn lower_in_stack() -> Color { c("#242427") }
/// `$card_insensitive_fg_color`: the header.
pub(crate) fn dim() -> Color { c("#afafb1") }
/// `%notification_button`: transparentize($fg_color, .85), .7 hovered.
pub(crate) fn button() -> Color { c("#ffffff").alpha(0.15) }
pub(crate) fn button_hover() -> Color { c("#ffffff").alpha(0.3) }
/// Adwaita's default accent.
pub(crate) fn accent() -> Color { c("#3584e4") }

/// A circular icon button (`.message-close-button`, `.message-collapse-button`).
pub(crate) fn round_button(key: &str, glyph: &str, size: f32, fill: Color, hover: Color) -> El {
    el().key(key).size(size, size).radius(size / 2.0).center().fill(fill).hover(hover).hit()
        .child(text(glyph.to_owned()).key("glyph").font(TextStyle::new(14.0, 400.0).family(rune::tok::Family::Named(crate::ICON_FAMILY))).color(fg()))
}

/// The cards overlay's state: everything it draws comes from `hub`.
#[derive(Default)]
pub struct Stack;

static HANDLE: OnceLock<OverlayHandle<Stack>> = OnceLock::new();
/// The monitor the stack is showing on.
static ON: Mutex<Option<String>> = Mutex::new(None);
/// Monitors with one of the bar's panels open: they show no cards.
static PANELS: Mutex<Option<HashSet<String>>> = Mutex::new(None);

/// One notification, as GNOME's `.message`: a header (source icon, app, time, close), the
/// picture on the left of the title and body, and the action buttons sharing a row.
/// `compact` is its entry in the bell's list: no shadow or slide, and × removes it from the
/// list rather than only hiding its card.
pub fn card<S: 'static>(n: &Note, compact: bool) -> El {
    let id = n.id;
    let mut source = row().key("source").grow(1.0).shrink().w(0.0).gap(6.0).items_center().child(icon(n))
        .child(text(n.app.clone()).key("app").font(HEADING).color(dim()).shrink().truncate());
    if let Some(cx) = &n.context { source = source.child(text(cx.clone()).key("context").font(CAPTION).color(dim()).shrink().truncate()); }
    let secs = n.time.duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    let header = row().key("header").w_full().px(6.0).gap(6.0).items_center().min_h(24.0)
        .child(source)
        .child(text(crate::clock::time(secs)).key("time").font(CAPTION).color(dim()));
    // × as a badge over the card's top-right corner, shown only while the card is hovered.
    let close = round_button("close", "\u{f0156}", 22.0, c("#4a4a4f"), c("#5a5a5f"))
        .pin(None, Some(-7.0), Some(-7.0), None).border(1.0, c("#ffffff").alpha(0.12))
        .shadow(1.0, 4.0, c("#000000").alpha(0.35)).group_opacity(0.0, 1.0)
        .on_press(move |_: &mut S| super::with(move |s, _| if compact { s.dismiss(id) } else { s.hide_card(id) }));
    let mut words = col().key("words").grow(1.0).shrink().w(0.0).gap(4.0);
    if !n.summary.is_empty() { words = words.child(text(n.summary.clone()).key("summary").font(HEADING).color(fg()).max_lines(2)); }
    if !n.body.is_empty() { words = words.child(text(n.body.clone()).key("body").font(BODY).color(fg()).max_lines(8)); }
    if let Some(v) = n.value {
        words = words.child(row().key("progress").w_full().h(4.0).mt(4.0).radius(2.0).fill(c("#ffffff").alpha(0.15)).clip_rounded(2.0)
            .child(el().key("done").w_frac(v).h_full().fill(accent())));
    }
    let mut content = row().key("content").w_full().padding(6.0).gap(6.0).items_center();
    if let Some(img) = &n.image_img {
        content = content.child(el().key("picture").size(48.0, 48.0).mr(6.0).pixels_fit(img.pixels(), rune::SurfaceFit::Fill));
    }
    let mut root = col().key(format!("note-{id}")).w_full().padding(6.0).child(header).child(content.child(words));
    if !n.actions.is_empty() {
        root = root.child(row().key("actions").w_full().padding(4.0).gap(6.0).children(n.actions.iter().map(|(key, label)| {
            let key = key.clone();
            row().key(format!("action-{key}")).grow(1.0).w(0.0).py(6.0).px(12.0).radius(8.0).justify_center().fill(button()).hover(button_hover()).hit()
                .child(text(label.clone()).key("label").font(HEADING).color(fg()).truncate())
                .on_press(move |_: &mut S| { let key = key.clone(); super::with(move |s, _| s.invoke(id, &key)) })
        })));
    }
    let has_default = n.has_default;
    // Click = the default action, else a card just goes (a list entry stays);
    // right-click dismisses, as hokum's.
    root = root.hit().on_press(move |_: &mut S| super::with(move |s, _| if has_default { s.invoke(id, "default") } else if compact { Vec::new() } else { s.hide_card(id) }))
        .on_secondary_press(move |_: &mut S, _, _| super::with(move |s, _| if compact { s.dismiss(id) } else { s.hide_card(id) }))
        .fill(message()).hover(message_hover()).child(close);
    if compact { return root.radius(18.0); }
    root.radius(16.0).min_h(64.0)
        .box_shadow(rune::Shadow { y: 2.0, blur: 4.0, spread: 2.0, color: c("#000000").alpha(0.2), ..Default::default() })
        .transition(Transition::asymmetric(
            Transition::offset(48.0, 0.0).combined(Transition::opacity()).combined(Transition::scale(0.97)),
            Transition::move_edge(rune::Edge::Trailing).combined(Transition::opacity()),
        ))
        .motion(rune::Spring::new(0.32, 0.12))
}

/// The header's source icon (16 pt), or the app's initial in a small circle.
fn icon(n: &Note) -> El {
    match &n.icon_img {
        Some(img) => el().key("icon").size(16.0, 16.0).pixels_fit(img.pixels(), rune::SurfaceFit::Fit),
        None => el().key("icon").size(16.0, 16.0).radius(8.0).center().fill(c("#ffffff").alpha(0.15))
            .child(text(n.app.chars().next().unwrap_or('?').to_uppercase().to_string()).key("initial").font(TextStyle::new(10.0, 700.0)).color(fg())),
    }
}

/// The stack: up to four cards, newest nearest the bar, and a "N more · Clear all" pill.
pub fn stack<S: 'static>(cards: &[&Note], more: usize) -> El {
    let bottom = vm_mode();
    let mut items: Vec<El> = cards.iter().map(|n| card::<S>(n, false)).collect();
    if more > 0 {
        items.push(row().key("more").h(32.0).px(14.0).gap(8.0).radius(16.0).center_y().fill(message()).hover(message_hover()).hit()
            .box_shadow(rune::Shadow { y: 2.0, blur: 4.0, spread: 2.0, color: c("#000000").alpha(0.2), ..Default::default() })
            .child(text(format!("{more} more")).key("count").font(BODY).color(dim()))
            .child(text("Clear").key("clear").font(HEADING).color(fg()))
            .on_press(|_: &mut S| super::with(|s, _| s.hide_cards()))
            .transition(Transition::opacity().combined(Transition::scale(0.9))));
    }
    if bottom { items.reverse(); }
    let (t, b) = if bottom { (None, Some(GUTTER)) } else { (Some(GUTTER), None) };
    col().key("stack").pin(None, t, Some(GUTTER), b).w(WIDTH).gap(8.0).items_end()
        .on_hover_change(|_: &mut S, inside, _| super::with(move |s, now| { s.pause(inside, now); Vec::new() }))
        .children(items)
}

pub fn view(_: &Stack, _: &mut Cx<Stack>) -> El {
    let d = crate::hub::data();
    let on = ON.lock().unwrap().clone();
    let held = on.is_some_and(|m| PANELS.lock().unwrap().as_ref().is_some_and(|p| p.contains(&m)));
    let (cards, more) = if held { (Vec::new(), 0) } else { d.notify.cards() };
    el().key("root").w_full().h_full().child(stack::<Stack>(&cards, more))
}

pub fn overlay() -> rune::ConfiguredOverlay<Stack> {
    OverlaySpec::new("andrew-notify", (WIDTH + 2.0 * GUTTER + 40.0, HEIGHT), view).options(OverlayOptions {
        // Margin 0: the compositor keeps it out of the bar's reserved strip.
        placement: Some(OverlayPlacement::Edge { edge: if vm_mode() { ScreenEdge::Bottom } else { ScreenEdge::Top }, margin: 0.0, align: Align::End, inset: 0.0 }),
        input: OverlayInput::Regions,
        ..Default::default()
    })
    // It hides while empty, so the first card arrives in the update that shows it.
    .animate_reveal()
}

pub fn set_handle(h: OverlayHandle<Stack>) { let _ = HANDLE.set(h); }

/// Re-renders the stack.
pub fn wake() { if let Some(h) = HANDLE.get() { h.update(|_, _| {}); } }

/// Records whether one of the bar's panels is open on `monitor`. Called from the bar's view,
/// so it must not take `hub`'s lock.
pub fn set_panel_open(monitor: &str, open: bool) {
    let mut p = PANELS.lock().unwrap();
    let set = p.get_or_insert_with(HashSet::new);
    let changed = if open { set.insert(monitor.to_owned()) } else { set.remove(monitor) };
    drop(p);
    if changed { wake(); }
}

/// Shows the overlay on the focused monitor when cards appear, and hides it a moment after
/// the last one leaves. Takes `hub`'s lock.
pub fn sync() {
    let Some(h) = HANDLE.get() else { return };
    // Locks in the view's order (hub, then ON); hyprctl runs with neither held, so a slow
    // Hyprland can't stall the UI thread.
    let showing = { let d = crate::hub::data(); let on = ON.lock().unwrap(); !d.notify.cards().0.is_empty() && on.is_none() };
    let monitor = if showing { focused_monitor() } else { None };
    let d = crate::hub::data();
    let mut on = ON.lock().unwrap();
    let any = !d.notify.cards().0.is_empty();
    if any && on.is_none() {
        if let Some(m) = &monitor { h.set_display(DisplayTarget::Name(m.clone())); }
        h.show();
        *on = Some(monitor.unwrap_or_default());
    } else if !any && on.is_some() {
        std::thread::spawn(|| {
            std::thread::sleep(HIDE_AFTER);
            // Both held while deciding, so a card arriving now can't be hidden with the overlay.
            let d = crate::hub::data();
            let mut on = ON.lock().unwrap();
            if d.notify.cards().0.is_empty() && on.take().is_some() && let Some(h) = HANDLE.get() { h.hide(); }
        });
    }
}

/// Hyprland's focused monitor.
fn focused_monitor() -> Option<String> {
    let out = std::process::Command::new("hyprctl").args(["-j", "monitors"]).output().ok()?;
    let list: Vec<serde_json::Value> = serde_json::from_slice(&out.stdout).ok()?;
    list.iter().find(|m| m["focused"] == true)?["name"].as_str().map(str::to_owned)
}

/// Notes that show off every part of a card, for `--notify-demo` (hokum's samples).
pub fn samples() -> Vec<Note> {
    let icon = |name: &str| crate::sources::icon_path(name, None).map(Picture::File);
    let mut a = Note::new(1, "Slack", "Dax", "hokum looks sick 👋 ship it before anyone sees the mako ones");
    a.context = Some("#general".into());
    a.actions = vec![("reply".into(), "Reply".into()), ("later".into(), "Later".into())];
    a.has_default = true;
    a.icon = icon("slack");
    let mut b = Note::new(2, "Volume", "Speakers", "");
    b.value = Some(0.62);
    b.tag = Some("volume".into());
    b.icon = icon("audio-volume-high");
    let mut f = Note::new(3, "Firefox", "Download complete", "hokum-x86_64.tar.zst · 4.2 MB");
    f.icon = icon("firefox");
    let mut d = Note::new(4, "Battery", "Battery critically low", "4% remaining. Plug in now or the session will suspend.");
    d.urgency = 2;
    d.timeout = Timeout::Never;
    let mut e = Note::new(5, "Slack", "Ana", "lunch at 1?");
    e.context = Some("Direct message".into());
    e.icon = a.icon.clone();
    vec![e, f, b, d, a]
}
