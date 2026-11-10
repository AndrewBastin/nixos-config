//! Andrew Shell's bar on Rune: one layer-shell panel per monitor, a port of the Quickshell bar
//! in `../../shell/config`. The panel surface is taller than the bar so tooltips and tray menus
//! draw inside it; only the bar's 33 points are reserved, and clicks outside hit elements pass
//! through to the windows underneath.

mod sources;
mod nm;
mod tray;
mod calendar;
mod sound;
mod wifi;
mod notify;
mod power;

use std::process::Command;

use rune::color::hex;
use rune::tok::Family;
use rune::{
    App, AppSpec, Color, Cx, DisplayTarget, El, OverlayHandle, OverlayInput, OverlayOptions, OverlayPlacement, OverlaySpec,
    RunOptions, ScreenEdge, TextStyle, Transition, WindowSpec, col, el, row, text,
};
use system_tray::client::ActivateRequest;
use system_tray::menu::{MenuItem, MenuType, ToggleState, ToggleType};

const BAR_H: f32 = 33.0;
/// Room under the bar for tooltips and menus.
const PANEL_H: f32 = BAR_H + 560.0;

// Qt points at 96 dpi, as the Quickshell bar sizes them: 10 pt = 13.33 px.
/// The Nerd Font the icons come from.
pub(crate) const ICON_FAMILY: &str = "BerkeleyMono Nerd Font";
pub(crate) const ICON_FONT: TextStyle = TextStyle::new(13.33, 400.0).family(Family::Named(ICON_FAMILY));
/// What the calendar's clicks open.
pub(crate) const CALENDAR_APP: &str = "thunderbird -calendar";
const ANIM_SPEED: f32 = 4.5;
const LABEL: TextStyle = TextStyle::new(12.0, 400.0);

fn c(s: &str) -> Color { hex(s).unwrap() }
fn bg() -> Color { c("#161616") }
fn fg() -> Color { c("#d8d8d8") }
pub fn accent() -> Color { c("#285577") }
fn urgent() -> Color { c("#B85F40") }
fn separator() -> Color { c("#565656") }
fn hover() -> Color { c("#ffffff").alpha(0.08) }

pub fn vm_mode() -> bool {
    static VM: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *VM.get_or_init(|| std::env::var("ANDREW_SHELL_VM_MODE").as_deref() == Ok("1"))
}

/// Everything the sources know, shared by every monitor's bar.
#[derive(Default)]
pub struct Data {
    pub hypr: sources::Hyprland,
    pub notify: notify::store::Store,
    pub events: Vec<sources::Event>,
    pub audio: sources::Audio,
    pub battery: Option<sources::Battery>,
    /// The battery panel's numbers, while it's open.
    pub power: Option<power::Stats>,
    pub tray: Vec<tray::Item>,
    pub wifi: sources::Wifi,
    pub vpns: Vec<sources::Vpn>,
    pub airpods: Option<sources::AirPods>,
    pub wired: Vec<sources::Wired>,
    pub now: i64,
    /// Resolved app icons by icon name; the handles keep the decoded images alive.
    pub app_icons: std::collections::HashMap<String, Option<rune::Image>>,
}

pub mod hub {
    use std::sync::{Mutex, MutexGuard, OnceLock};

    use super::{Bar, Data};

    static DATA: OnceLock<Mutex<Data>> = OnceLock::new();
    static BARS: Mutex<Vec<rune::OverlayHandle<Bar>>> = Mutex::new(Vec::new());
    static IMAGES: OnceLock<rune::ImageCache> = OnceLock::new();

    pub fn data() -> MutexGuard<'static, Data> { DATA.get_or_init(Default::default).lock().unwrap() }

    pub fn wake() {
        for bar in BARS.lock().unwrap().iter() { bar.update(|_, _| {}); }
        crate::notify::cards::wake();
    }

    /// Changes the shared data, then re-renders every bar.
    pub fn set(f: impl FnOnce(&mut Data)) {
        f(&mut data());
        wake();
    }

    /// Sets one field of the shared data, re-rendering the bars only if it changed: most
    /// source updates repeat what's shown.
    pub fn put<T: PartialEq>(field: impl FnOnce(&mut Data) -> &mut T, value: T) {
        let mut d = data();
        let slot = field(&mut d);
        if *slot == value { return; }
        *slot = value;
        drop(d);
        wake();
    }

    /// Re-renders only the bars `shows` picks: for data seen only inside a panel, which a bar
    /// opening it later reads fresh from here as it rebuilds.
    pub fn wake_where(shows: fn(&Bar) -> bool) {
        for bar in BARS.lock().unwrap().iter() { bar.update_if(move |b, _| shows(b)); }
    }

    /// `set` for data seen only where `shows` picks (see `wake_where`).
    pub fn set_where(shows: fn(&Bar) -> bool, f: impl FnOnce(&mut Data)) {
        f(&mut data());
        wake_where(shows);
    }

    pub fn add_bar(bar: rune::OverlayHandle<Bar>) { BARS.lock().unwrap().push(bar); }

    pub fn bar(i: usize) -> rune::OverlayHandle<Bar> { BARS.lock().unwrap()[i].clone() }

    pub fn each_bar(f: impl Fn(&rune::OverlayHandle<Bar>)) { BARS.lock().unwrap().iter().for_each(f); }

    pub fn images() -> &'static rune::ImageCache {
        IMAGES.get_or_init(|| rune::ImageCache::new(std::sync::Arc::new(wake)))
    }

    /// Resolves the icons not seen before. The icon directories are searched without the data
    /// lock held, which drawing needs.
    pub fn app_icons<'a>(names: impl Iterator<Item = &'a str>) {
        let new: Vec<&str> = { let d = data(); names.filter(|n| !d.app_icons.contains_key(*n)).collect() };
        if new.is_empty() { return; }
        let found: Vec<_> = new.iter().map(|n| (n.to_string(), crate::sources::icon_path(n, None).map(|p| images().file(p, 24.0, 2.0)))).collect();
        set(|d| d.app_icons.extend(found));
    }
}

/// One thread runs every D-Bus task (NetworkManager, UPower, the tray, notifications), and the
/// system-bus ones share a connection.
// ponytail: a task that blocks (the tray's first icon lookups) stalls the others for that long.
pub mod rt {
    use std::sync::OnceLock;

    fn handle() -> &'static tokio::runtime::Handle {
        static H: OnceLock<tokio::runtime::Handle> = OnceLock::new();
        H.get_or_init(|| {
            let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().expect("tokio runtime");
            let h = rt.handle().clone();
            let _ = std::thread::Builder::new().name("dbus".into()).spawn(move || rt.block_on(std::future::pending::<()>()));
            h
        })
    }

    pub fn spawn(f: impl Future<Output = ()> + Send + 'static) { handle().spawn(f); }

    /// Runs `f` to the end from a thread outside the runtime.
    pub fn block_on<T>(f: impl Future<Output = T>) -> T { handle().block_on(f) }

    pub async fn system() -> zbus::Result<zbus::Connection> {
        static SYSTEM: tokio::sync::OnceCell<zbus::Connection> = tokio::sync::OnceCell::const_new();
        SYSTEM.get_or_try_init(zbus::Connection::system).await.cloned()
    }

    /// The system bus's signals matching `rule`, drained by their own task. zbus stops reading
    /// the connection (replies included) while a filtered stream holds 64 unread messages, so
    /// a watcher awaiting a call while its signals pile up (NetworkManager's burst on resume)
    /// would wait forever, and wedge every other system-bus task with it.
    pub async fn system_signals(rule: zbus::MatchRule<'static>) -> zbus::Result<(zbus::Connection, tokio::sync::mpsc::UnboundedReceiver<zbus::Message>)> {
        use futures_util::StreamExt;
        let conn = system().await?;
        let mut stream = zbus::MessageStream::for_match_rule(rule, &conn, None).await?;
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        spawn(async move {
            while let Some(m) = stream.next().await {
                if let Ok(m) = m && tx.send(m).is_err() { break; }
            }
        });
        Ok((conn, rx))
    }
}

pub mod clock {
    pub fn now() -> i64 { std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64) }

    pub fn local(t: i64) -> libc::tm {
        // SAFETY: localtime_r writes only the tm we hand it.
        unsafe {
            let mut tm: libc::tm = std::mem::zeroed();
            libc::localtime_r(&t, &mut tm);
            tm
        }
    }

    /// "h:mm AM"
    pub fn time(t: i64) -> String {
        let tm = local(t);
        let h = match tm.tm_hour % 12 { 0 => 12, h => h };
        format!("{h}:{:02} {}", tm.tm_min, if tm.tm_hour < 12 { "AM" } else { "PM" })
    }

    /// "Tue Nov 03 5:42 PM", Qt's "ddd MMM dd h:mm AP".
    pub fn date_time(t: i64) -> String {
        const DAYS: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        const MONTHS: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        let tm = local(t);
        format!("{} {} {:02} {}", DAYS[tm.tm_wday as usize % 7], MONTHS[tm.tm_mon as usize % 12], tm.tm_mday, time(t))
    }
}

/// One monitor's bar: which monitor it is, plus what only this bar's pointer did.
#[derive(Default)]
pub struct Bar {
    monitor: String,
    tray_open: bool,
    /// The tray item address whose menu is open, and the submenus expanded in it.
    menu: Option<String>,
    expanded: Vec<i32>,
    /// The open menu or panel's scrollbar (one is open at a time).
    thumb: Thumb,
    /// When the meeting link was copied; the calendar shows a check for 1.5 s.
    copied: Option<std::time::Instant>,
    dismissed: i64,
    /// Laid-out rects (window points) of the workspaces row and each pill, for the highlight.
    ws_row: [f32; 4],
    ws_rects: std::collections::HashMap<i64, [f32; 4]>,
    wifi_open: bool,
    /// "Other Networks" disclosed.
    others_open: bool,
    /// The panel shows the VPN page instead of the main one.
    vpn_open: bool,
    /// The Wi-Fi panel switched pages since it opened, so the pages slide.
    vpn_slid: bool,
    sound_open: bool,
    calendar_open: bool,
    /// The AirPods controls are expanded under their output row.
    airpods_open: bool,
    /// The volume the slider shows while it's dragged, and from its release until PipeWire
    /// has caught up (`sound::HOLD`), so the knob doesn't jump back.
    vol_hold: Option<(f32, Option<std::time::Instant>)>,
    /// The bell's notification list is open.
    notify_open: bool,
    /// Apps whose notification groups are expanded in it.
    notify_expanded: std::collections::HashSet<String>,
    /// The battery item's panel is open.
    power_open: bool,
    /// Its sampler's generation (`power::close` stops only that one).
    power_gen: u64,
    /// This bar holds a focus grab, so a click anywhere off it closes what's open.
    grabbed: bool,
}

impl Bar {
    fn new(monitor: String) -> Bar {
        Bar { monitor, ..Default::default() }
    }

    /// A menu or panel is open: clicks elsewhere close it, and this monitor shows no cards.
    pub(crate) fn any_open(&self) -> bool { self.menu.is_some() || self.wifi_open || self.sound_open || self.calendar_open || self.notify_open || self.power_open }
}

/// Headless `--notify-demo`: the bar's own view draws the card stack, for `--snap`.
fn headless_demo() -> bool {
    static DEMO: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *DEMO.get_or_init(|| std::env::args().any(|a| a == "--notify-demo") && std::env::args().any(|a| a.starts_with("--snap")))
}

fn spawn(cmd: &str, args: &[&str]) {
    if let Err(e) = Command::new(cmd).args(args).spawn() { eprintln!("andrew-bar: {cmd}: {e}"); }
}

/// A Nerd Font icon in a box as wide as its ink, as Qt's `Text` lays it out. Rune sizes text by
/// advance, and the mono font's wide icons overflow their cell, which made gaps uneven.
fn icon_text(s: impl Into<String>) -> El {
    let s = s.into();
    match ink(&s, ICON_FONT.size) {
        Some([left, width, ..]) => el().w(width).child(text(s).font(ICON_FONT).color(fg()).ml(-left)),
        None => text(s).font(ICON_FONT).color(fg()),
    }
}

/// The ink box of `s` in the icon font at `size` points, relative to its text box:
/// [left, width, top, height]. Rune measures it as drawn, and caches it.
fn ink(s: &str, size: f32) -> Option<[f32; 4]> {
    let [x, y, w, h] = rune::text::ink(s, TextStyle { size, ..ICON_FONT })?.bounds;
    Some([x, w, y, h])
}

/// A Nerd Font glyph in a box exactly its ink, so centring it centres what's drawn.
fn glyph(s: &str, size: f32, color: Color) -> El {
    let t = text(s).font(TextStyle { size, ..ICON_FONT }).color(color);
    match ink(s, size) {
        Some([left, width, top, height]) => el().size(width, height).child(t.ml(-left).mt(-top)),
        None => t,
    }
}

/// A hoverable, pressable status slot.
fn slot(key: impl Into<String>, child: El) -> El {
    let key = key.into();
    // The negative margin keeps the hover pad out of layout, so spacing matches Quickshell's.
    // No press_scale: a slot's popup hangs inside it, and would shrink with it while held.
    el().key(key.as_str()).px(4.0).py(2.0).mx(-4.0).radius(4.0).hover(hover()).hit().center().child(child)
}

fn sep(key: &str) -> El { el().key(key).w(1.0).h(18.0).fill(separator()) }

fn app_icon(d: &Data, name: Option<&str>, size: f32, key: String) -> El {
    match name.and_then(|n| d.app_icons.get(n)).and_then(|i| i.as_ref()) {
        Some(img) => el().key(key.as_str()).size(size, size).pixels(img.pixels()),
        // Boxed like a real icon: bare text is sized by advance, and the wide glyph overflowed it.
        None => el().key(key.as_str()).size(size, size).center().child(glyph("\u{f2d0}", size * 0.65, fg())),
    }
}

fn workspaces(s: &Bar, d: &Data) -> El {
    let mut r = row().key("workspaces").gap(4.0).items_center().on_layout(|s: &mut Bar, rect| s.ws_row = rect);
    let list = d.hypr.monitors.get(&s.monitor).map(|m| m.workspaces.as_slice()).unwrap_or_default();
    // One highlight under the pills that springs to the active one's rect. A `matched` flight
    // would paint above the pills and hide the target's number until it lands.
    if let Some(a) = list.iter().find(|w| w.active).and_then(|w| s.ws_rects.get(&w.id)) {
        r = r.child(el().key("ws-highlight").absolute(a[0] - s.ws_row[0], a[1] - s.ws_row[1]).size(a[2], a[3]).radius(5.0).fill(accent()));
    }
    for w in list {
        let name = if w.name == "special:magic" { "SP".to_owned() } else { w.name.clone() };
        let key = format!("ws-{}", w.id);
        let id = w.id;
        let mut pill = row().key(key.as_str()).gap(4.0).px(5.0).py(4.0).radius(5.0).items_center()
            .transition(Transition::scale(0.8)).on_layout(move |s: &mut Bar, rect| { s.ws_rects.insert(id, rect); });
        if w.urgent && !w.active {
            pill = pill.fill(urgent());
        }
        pill = pill.child(text(name).key("name").font(LABEL).color(fg()));
        for (i, t) in w.toplevels.iter().enumerate() {
            pill = pill.child(app_icon(d, t.icon_name.as_deref(), 16.5, format!("app-{i}")).transition(Transition::scale(0.5)));
        }
        r = r.child(pill);
    }
    r.child(sep("ws-sep"))
}

fn current_window(d: &Data) -> El {
    let Some(w) = &d.hypr.active_window else { return el().key("window") };
    let title: String = if w.title.chars().count() > 120 { w.title.chars().take(117).chain("...".chars()).collect() } else { w.title.clone() };
    row().key("window").gap(6.0).items_center().min_w(0.0)
        .child(app_icon(d, w.icon_name.as_deref(), 20.0, format!("win-icon-{}", w.icon_name.as_deref().unwrap_or(""))).transition(Transition::blur_replace()))
        .child(text(title).key("title").font(LABEL).color(fg()).truncate())
}

pub fn volume_glyph(a: &sources::Audio) -> &'static str {
    if a.muted { "\u{f075f}" } else if a.volume == 0 { "\u{f026}" } else if a.volume <= 50 { "\u{f027}" } else { "\u{f028}" }
}

fn audio(s: &Bar, d: &Data) -> El {
    let a = &d.audio;
    let glyph = volume_glyph(a);
    let tip = if a.muted { format!("{} - Muted", a.name) } else { format!("{} - {}%", a.name, a.volume) };
    // Quickshell's "  " before the Bluetooth glyph is in its narrow default font and the speaker's
    // ink spills over it, so the two glyphs sit almost touching; a mono-font space would not.
    let mut icons = row().key("icons").gap(1.5).items_center().child(icon_text(glyph).key(glyph));
    if a.bluetooth { icons = icons.child(icon_text("\u{f294}").key("bt").transition(Transition::opacity())); }
    let mut e = slot("audio", icons).on_press(|s: &mut Bar| sound::toggle_panel(s));
    if !s.sound_open { e = e.help(tip); }
    if let Some(p) = sound::panel(s, d) { e = e.child(p); }
    e
}

pub fn battery_glyph(percent: u32) -> &'static str {
    [(5, "\u{f008e}"), (10, "\u{f007a}"), (20, "\u{f007b}"), (30, "\u{f007c}"), (40, "\u{f007d}"), (50, "\u{f007e}"),
        (60, "\u{f007f}"), (70, "\u{f0080}"), (80, "\u{f0081}"), (95, "\u{f0082}")]
        .iter().find(|(max, _)| percent <= *max).map_or("\u{f0079}", |(_, g)| g)
}

fn battery(s: &Bar, d: &Data) -> El {
    let Some(b) = &d.battery else { return el().key("battery") };
    let glyph = battery_glyph(b.percent);
    let status = match (&b.time, b.charging) {
        (Some(t), true) => format!("Charging - {t} until full"),
        (None, true) => "Charging".into(),
        (Some(t), false) => format!("{t} remaining"),
        (None, false) => String::new(),
    };
    let mut e = slot("battery", icon_text(glyph)).on_press(power::toggle_panel);
    if !s.power_open { e = e.help(format!("{}% {status}", b.percent).trim().to_owned()); }
    if let Some(p) = power::panel(s, d) { e = e.child(p); }
    e
}

fn calendar(s: &Bar, d: &Data) -> Option<El> {
    if d.notify.dnd { return None; }
    let e = d.events.iter().find(|e| e.start > d.now && e.start != s.dismissed)?;
    let minutes = (e.start - d.now + 59) / 60;
    if minutes > 60 { return None; }
    // The glyph in the icon font, the countdown in the bar's text font (as the clock), like
    // Quickshell's label, whose digits fall back to its default sans.
    let label = if s.copied.is_some() { icon_text("\u{f012c}").key("copied") } else {
        row().key("countdown").gap(9.0).items_center().child(icon_text("\u{f00ed}").key("glyph"))
            .child(text(format!("{minutes}m")).key("minutes").font(LABEL).color(fg()))
    };
    let hint = if e.url.is_some() { "Click: copy meeting link · Right-click: dismiss" } else { "Click: open Thunderbird · Right-click: dismiss" };
    let (url, start) = (e.url.clone(), e.start);
    Some(slot("calendar", label)
        .help(format!("{} · {} ({})\n\n{hint}", e.title, clock::time(e.start), e.calendar))
        .on_press_tx(move |s: &mut Bar, tx| match &url {
            Some(url) => {
                tx.copy(url.clone());
                s.copied = Some(std::time::Instant::now());
                tx.wake_after(COPIED);
            }
            None => spawn("hyprctl", &["dispatch", "exec", CALENDAR_APP]),
        })
        .on_secondary_press(move |s: &mut Bar, _, _| s.dismissed = start))
}

fn strip_mnemonic(label: &str) -> String {
    let mut out = String::new();
    let mut chars = label.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '_' { if chars.peek() == Some(&'_') { out.push('_'); chars.next(); } } else { out.push(ch); }
    }
    out
}

fn menu_rows(s: &Bar, item: &tray::Item, entries: &[MenuItem], depth: f32, out: &mut Vec<El>) {
    for m in entries.iter().filter(|m| m.visible) {
        let key = format!("menu-{}", m.id);
        if m.menu_type == MenuType::Separator {
            out.push(el().key(key.as_str()).h(1.0).mx(6.0).my(3.0).fill(c("#ffffff").alpha(0.1)));
            continue;
        }
        let check = match (m.toggle_type, m.toggle_state) {
            (ToggleType::Checkmark | ToggleType::Radio, ToggleState::On) => "\u{f012c}",
            _ => "",
        };
        let has_sub = !m.submenu.is_empty();
        let open = s.expanded.contains(&m.id);
        let label = strip_mnemonic(m.label.as_deref().unwrap_or(""));
        let mut r = row().key(key.as_str()).gap(8.0).pl(8.0 + depth * 14.0).pr(10.0).py(5.0).radius(5.0).items_center()
            .opacity(if m.enabled { 1.0 } else { 0.45 })
            .child(el().key("check").w(14.0).child(icon_text(check)))
            .child(text(label).key("label").font(LABEL).color(fg()).grow(1.0));
        if has_sub {
            r = r.child(icon_text("\u{f0142}").key("chevron").rotate(if open { std::f32::consts::FRAC_PI_2 } else { 0.0 }));
        }
        if m.enabled {
            let (id, address, path) = (m.id, item.address.clone(), item.menu_path.clone().unwrap_or_default());
            r = r.hover(hover()).hit().on_press(move |s: &mut Bar| {
                if has_sub {
                    if let Some(i) = s.expanded.iter().position(|e| *e == id) { s.expanded.remove(i); } else { s.expanded.push(id); }
                } else {
                    tray::activate(ActivateRequest::MenuItem { address: address.clone(), menu_path: path.clone(), submenu_id: id });
                    s.menu = None;
                }
            });
        }
        out.push(r);
        if has_sub && open { menu_rows(s, item, &m.submenu, depth + 1.0, out); }
    }
}

/// How a popup (the tray menu, a status item's panel) opens: a quick scale out of the bar,
/// as macOS's menus, faster than Rune's default settle (0.3 s in, 0.24 s out).
pub(crate) fn popup() -> Transition {
    Transition::scale_anchor(0.94, rune::Vec2 { x: 1.0, y: 0.0 })
        .springs(rune::SpringPair::new(rune::Spring::new(0.16, 0.0), rune::Spring::new(0.12, 0.0)))
}

/// The open tray menu, hanging from the right edge of the item it belongs to.
fn menu(s: &Bar, item: &tray::Item) -> Option<El> {
    if s.menu.as_deref() != Some(item.address.as_str()) { return None; }
    let entries = item.menu.as_ref().map(|m| m.submenus.as_slice()).unwrap_or_default();
    let mut rows = Vec::new();
    menu_rows(s, item, entries, 0.0, &mut rows);
    if rows.is_empty() { rows.push(text("No menu").key("empty").font(LABEL).color(fg()).padding(8.0)); }
    let frame = col().key("menu").pin(None, (!vm_mode()).then_some(BAR_H - 2.0), Some(-6.0), vm_mode().then_some(BAR_H - 2.0)).w(300.0).max_h(PANEL_H - BAR_H - 12.0)
        .radius(8.0).fill(c("#1f1f1f")).border(1.0, c("#ffffff").alpha(0.08)).shadow(8.0, 24.0, c("#000000").alpha(0.45)).clip_rounded(8.0)
        .hit().transition(popup());
    Some(scroller(s, frame, 300.0, PANEL_H - BAR_H - 14.0, col().key("menu-list").padding(5.0).children(rows)))
}

/// A scrollbar thumb's place, set as its viewport scrolls; kept in `Bar` so it outlives the
/// view's rebuilds (the viewport only reports when it moves).
#[derive(Clone)]
pub struct Thumb(rune::Live<[f32; 4]>);
impl Default for Thumb { fn default() -> Self { Self(rune::Live::new([0.0; 4])) } }

/// `frame` (a popup `w` wide whose list is capped at `cap` tall) around `list` as a scroll
/// viewport, with a thin scrollbar at the right while the list overflows.
pub fn scroller(s: &Bar, frame: El, w: f32, cap: f32, list: El) -> El {
    let live = s.thumb.0.clone();
    let list = list.w_full().shrink().min_h(0.0).scroll(rune::ScrollSpec { stick_bottom: false }).scroll_edge_fade(44.0)
        .on_scroll_offset(move |at: rune::ScrollPos| {
            let max = at.max[1];
            if max <= 0.5 { live.set([0.0; 4]); return; }
            // Overflowing, the viewport is at its cap.
            let track = cap - 8.0;
            let h = (track * cap / (cap + max)).max(28.0);
            live.set([w - 7.0, 4.0 + (track - h) * (at.offset[1] / max).clamp(0.0, 1.0), 4.0, h]);
        });
    frame.child(list).child(el().key("scroll-thumb").absolute(0.0, 0.0).w(4.0).h(1.0).radius(2.0).fill(c("#ffffff").alpha(0.3)).live_rect(&s.thumb.0))
}

fn toggle_menu(s: &mut Bar, address: &str) {
    let open = s.menu.as_deref() != Some(address);
    close_popups(s);
    s.expanded.clear();
    if open { s.menu = Some(address.to_owned()); }
}

/// Closes whichever tray menu or panel is open, on every monitor: at most one is open
/// anywhere. Every toggle calls this before opening its own.
pub fn close_popups(s: &mut Bar) {
    close_here(s);
    let monitor = s.monitor.clone();
    hub::each_bar(|bar| {
        let monitor = monitor.clone();
        // Only a bar that had something open rebuilds.
        bar.update_if(move |b, _| { let open = b.monitor != monitor && b.any_open(); if open { close_here(b) } open });
    });
}

fn close_here(s: &mut Bar) {
    s.menu = None;
    wifi::close(s);
    sound::close(s);
    calendar::close(s);
    notify::panel::close(s);
    power::close(s);
}

fn tray_item(s: &Bar, item: &tray::Item) -> El {
    let icon = match &item.icon {
        Some(img) => el().key("icon").size(14.0, 14.0).pixels(img.pixels()),
        None => icon_text("\u{f059f}").key("icon"),
    };
    let address = item.address.clone();
    let (has_menu, only_menu) = (item.menu.is_some(), item.item_is_menu);
    let a2 = address.clone();
    let mut e = slot(format!("tray-{}", item.id), icon).transition(Transition::scale(0.6))
        .on_press(move |s: &mut Bar| if only_menu { toggle_menu(s, &address) } else {
            tray::activate(ActivateRequest::Default { address: address.clone(), x: 0, y: 0 });
        })
        .on_secondary_press(move |s: &mut Bar, _, _| if has_menu { toggle_menu(s, &a2) } else {
            tray::activate(ActivateRequest::Secondary { address: a2.clone(), x: 0, y: 0 });
        });
    if !item.title.is_empty() && s.menu.is_none() { e = e.help(item.title.clone()); }
    if let Some(m) = menu(s, item) { e = e.child(m); }
    e
}

fn concealed(s: &Bar, d: &Data) -> El {
    let chevron = slot("chevron", text("\u{f0141}").key("glyph").font(TextStyle::new(18.67, 400.0).family(Family::Named(ICON_FAMILY)))
        .color(separator()).rotate(if s.tray_open { std::f32::consts::PI } else { 0.0 }))
        .on_press(|s: &mut Bar| { s.tray_open = !s.tray_open; if !s.tray_open { s.menu = None; } });
    // pr(5): the collapsed Quickshell group keeps its RowLayout's default 5 pt spacing.
    let mut group = row().key("concealed").gap(13.0).pr(5.0).items_center().child(chevron);
    if s.tray_open {
        let mut icons = row().key("tray").gap(13.0).items_center().transition(Transition::reveal(rune::Edge::Trailing));
        for item in &d.tray { icons = icons.child(tray_item(s, item)); }
        group = group.child(icons.child(sep("tray-sep")));
    }
    group
}

pub fn view(s: &Bar, cx: &mut Cx<Bar>) -> El {
    // Every spring, fade and hover runs on this clock: >1 is snappier than Rune's defaults.
    cx.time_scale(ANIM_SPEED);
    let d = hub::data();
    let vm = vm_mode();
    let mut right = row().key("right").gap(13.0).items_center().child(concealed(s, &d));
    if !vm { right = right.child(audio(s, &d)).child(wifi::status(s, &d)).child(battery(s, &d)); }
    right = right.child(notify::panel::status(s, &d));
    if !vm && let Some(cal) = calendar(s, &d) { right = right.child(cal); }
    if !vm { right = right.child(calendar::clock(s, &d)); }

    let bar = row().key("bar").w_full().h(BAR_H).px(10.0).gap(10.0).items_center().justify_between().fill(bg()).hit()
        .child(row().key("left").gap(8.0).items_center().min_w(0.0).shrink().child(workspaces(s, &d)).child(current_window(&d)))
        .child(right);
    // In VM mode the panel sits on the bottom edge, so the bar is the surface's last strip.
    let mut root = col().key("root").w_full().h_full();
    if vm { root = root.justify_end(); }
    let open = s.any_open();
    notify::cards::set_panel_open(&s.monitor, open);
    if headless_demo() && !open {
        let (cards, more) = d.notify.cards();
        root = root.child(el().key("notify-demo").pin(Some(0.0), Some(BAR_H), Some(0.0), Some(0.0)).child(notify::cards::stack::<Bar>(&cards, more)));
    }
    if open {
        // Clicking anywhere else under the bar closes the menu or panel.
        let dismiss = |s: &mut Bar| close_popups(s);
        root = root.child(el().key("dismiss").pin(Some(0.0), Some(0.0), Some(0.0), Some(0.0)).hit()
            .on_press(dismiss).on_secondary_press(move |s: &mut Bar, _, _| dismiss(s)));
    }
    root.child(bar)
}

/// Holds a focus grab while a menu or panel is open: the `dismiss` layer only sees clicks on
/// this surface, the grab sees clicks on windows, the desktop and other monitors.
fn sync_grab(s: &mut Bar) {
    let open = s.any_open();
    if open == s.grabbed { return; }
    s.grabbed = open;
    let Some(i) = BAR_MONITORS.lock().unwrap().iter().position(|m| m.as_ref() == Some(&s.monitor)) else { return };
    let bar = hub::bar(i);
    // Only this bar: another monitor's may have opened its own panel with that same click.
    if open { bar.grab(|s, _| close_here(s)) } else { bar.ungrab() }
}

const COPIED: std::time::Duration = std::time::Duration::from_millis(1500);

fn poll(s: &mut Bar, _: f64, _: &mut rune::Tx) -> bool {
    sync_grab(s);
    let done = s.copied.is_some_and(|t| t.elapsed() >= COPIED);
    if done { s.copied = None; }
    done
}

fn main() {
    sources::start();
    if !vm_mode() { tray::start(); }
    let headless = std::env::args().any(|a| a.starts_with("--snap") || a == "--tree");
    if !headless { notify::start(); }
    if !headless && !vm_mode() { power::start(); }
    let demo = std::env::args().any(|a| a == "--notify-demo");
    if demo { notify::demo(); }
    // Headless snaps run on virtual time: sample before the frame, so the battery panel has numbers.
    if headless && std::env::args().any(|a| a == "--power-demo") { power::demo(); }
    if headless {
        // Let the sources fill in before the one rendered frame.
        std::thread::sleep(std::time::Duration::from_millis(1500));
    }
    let mut spec = AppSpec::new("andrew-bar", (1600.0, PANEL_H), || Bar::new(first_monitor()), view);
    spec.poll = Some(poll);
    spec.fonts = icon_font();
    if headless {
        rune::run(spec);
        return;
    }
    rune::run_windows_with(RunOptions { accessory: true }, move |displays| {
        let mut app = App::new(spec).windowless();
        let mut slots = BAR_MONITORS.lock().unwrap();
        for i in 0..BAR_POOL {
            let d = displays.get(i);
            let monitor = d.and_then(|d| d.name.clone());
            let width = d.map_or(1600.0, |d| d.size.0 as f32);
            let bar: OverlayHandle<Bar> = app.overlay(OverlaySpec::new("andrew-bar", (width, PANEL_H), view).options(OverlayOptions {
                placement: Some(OverlayPlacement::Panel {
                    edge: if vm_mode() { ScreenEdge::Bottom } else { ScreenEdge::Top }, height: PANEL_H, exclusive: BAR_H,
                }),
                display: monitor.clone().map_or(DisplayTarget::Primary, DisplayTarget::Name),
                input: OverlayInput::Regions,
                ..Default::default()
            }).poll(poll), Bar::new(monitor.clone().unwrap_or_default()));
            if let Some(d) = d {
                eprintln!("andrew-bar: bar on {} ({}x{} @ {})", monitor.as_deref().unwrap_or(""), d.size.0, d.size.1, d.scale);
                bar.show();
                // An unnamed display still gets a bar; the first monitor check reassigns it.
                slots.push(Some(monitor.unwrap_or_default()));
            } else {
                slots.push(None);
            }
            hub::add_bar(bar);
        }
        let cards = app.overlay(notify::cards::overlay(), notify::cards::Stack);
        notify::cards::set_handle(cards);
        if displays.len() > BAR_POOL { eprintln!("andrew-bar: {} displays, only {BAR_POOL} bars", displays.len()); }
        drop(slots);
        vec![WindowSpec::from_app("bar", app)]
    });
}

/// Bar overlays made at startup and handed out to monitors as they come and go.
// ponytail: a fixed pool; monitors beyond it get no bar. Raise it if that ever happens.
const BAR_POOL: usize = 4;

/// The monitor each pooled bar (by `hub` index) is on; None while it's hidden.
static BAR_MONITORS: std::sync::Mutex<Vec<Option<String>>> = std::sync::Mutex::new(Vec::new());

/// Gives each Hyprland monitor a bar from the pool when the monitor set changes, and hides
/// the bars of monitors that went away. Called on every Hyprland update; waits for the set
/// to settle first.
pub fn check_monitors() {
    static PENDING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
    let current = || { let mut m: Vec<String> = hub::data().hypr.monitors.keys().cloned().collect(); m.sort(); m };
    let assigned = || { let mut m: Vec<String> = BAR_MONITORS.lock().unwrap().iter().flatten().cloned().collect(); m.sort(); m };
    // Before the pool exists there is nothing to reassign.
    if BAR_MONITORS.lock().unwrap().is_empty() { return; }
    if current() == assigned() || PENDING.swap(true, std::sync::atomic::Ordering::SeqCst) { return; }
    std::thread::spawn(move || {
        // Let a dock's outputs all arrive, and winit see them, before reassigning.
        std::thread::sleep(std::time::Duration::from_millis(1500));
        PENDING.store(false, std::sync::atomic::Ordering::SeqCst);
        let current = current();
        let mut slots = BAR_MONITORS.lock().unwrap();
        for (i, slot) in slots.iter_mut().enumerate() {
            if slot.as_ref().is_some_and(|m| !current.contains(m)) {
                eprintln!("andrew-bar: {} gone; hiding its bar", slot.as_deref().unwrap_or(""));
                hub::bar(i).hide();
                *slot = None;
            }
        }
        for m in current {
            if slots.contains(&Some(m.clone())) { continue; }
            let Some(i) = slots.iter().position(Option::is_none) else { eprintln!("andrew-bar: no free bar for {m}"); continue };
            eprintln!("andrew-bar: bar on {m}");
            let bar = hub::bar(i);
            // A fresh state: the bar's popups closed, showing this monitor's workspaces. Keep the
            // laid-out rects: Rune fires `on_layout` only when a rect moves, so pills that come
            // back in the same place (a monitor re-plugged) would never report again.
            let monitor = m.clone();
            bar.update(move |s, _| *s = Bar { ws_row: s.ws_row, ws_rects: std::mem::take(&mut s.ws_rects), ..Bar::new(monitor) });
            bar.set_display(DisplayTarget::Name(m.clone()));
            bar.show();
            slots[i] = Some(m);
        }
    });
}

fn first_monitor() -> String {
    let d = hub::data();
    let mut names: Vec<&String> = d.hypr.monitors.keys().collect();
    names.sort();
    names.first().map(|s| s.to_string()).unwrap_or_default()
}

/// The Nerd Font file fontconfig finds, for `ICON_FONT`. Rune only names fonts it's handed.
fn icon_font() -> &'static [&'static [u8]] {
    let out = Command::new("fc-match").args(["-f", "%{file}", ICON_FAMILY]).output();
    match out.ok().and_then(|o| std::fs::read(String::from_utf8_lossy(&o.stdout).as_ref()).ok()) {
        Some(bytes) => {
            let bytes: &'static [u8] = Box::leak(bytes.into_boxed_slice());
            Box::leak(vec![bytes].into_boxed_slice())
        }
        None => { eprintln!("andrew-bar: {ICON_FAMILY} not found; icons fall back to Inter"); &[] }
    }
}
