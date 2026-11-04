//! A network status item and panel laid out like macOS's Wi-Fi menu, with Ethernet and VPN
//! sections stacked under Wi-Fi. Fed by NetworkManager over DBus (`nm`), with nmcli for the
//! actions. It replaces the nm-applet item.
//! Passwords are never typed here: NetworkManager asks its secret agent (nm-applet's dialog).

use rune::{Color, El, TextStyle, Transition, col, el, row, text};

use crate::sources::{self, Link, Vpn, WifiNet, Wired};
use crate::{Bar, Data, LABEL, accent, c, fg, glyph, hover, icon_text, slot};

const PANEL_W: f32 = 300.0;
const SMALL: TextStyle = TextStyle::new(11.0, 600.0);
pub(crate) const TITLE: TextStyle = TextStyle::new(13.0, 600.0);

pub(crate) fn muted() -> Color { c("#ffffff").alpha(0.5) }

/// The nm-applet item's signal-bar glyphs (nm-signal-00..100), at nm-applet's thresholds.
fn strength_glyph(signal: u8) -> &'static str {
    match signal {
        81.. => "\u{f08fa}",
        56.. => "\u{f08f8}",
        31.. => "\u{f08f6}",
        6.. => "\u{f08f4}",
        _ => "\u{f08fe}",
    }
}

// The nm-applet item's glyphs (see `blocks/Network.qml`).
const WIRED_GLYPH: &str = "\u{f0200}";
const VPN_GLYPH: &str = "\u{f099d}";

/// The bar glyph, as nm-applet picks it: wired when a cable is connected, else the joined
/// network's strength, else nm-no-connection's.
fn bar_glyph(d: &Data) -> &'static str {
    if d.wired.iter().any(|w| w.link == Link::On) { return WIRED_GLYPH; }
    let joined = d.wifi.networks.iter().find(|n| n.active).filter(|_| d.wifi.enabled);
    joined.map_or("\u{f0319}", |n| strength_glyph(n.signal))
}

pub fn status(s: &Bar, d: &Data) -> El {
    let glyph = bar_glyph(d);
    let mut icons = row().key("icons").gap(1.5).items_center().child(icon_text(glyph).key(glyph).transition(Transition::blur_replace()));
    // A VPN badge beside it while one is up (dimmed while it connects), as the applet shows it.
    let vpn = d.vpns.iter().map(|v| v.link).max_by_key(|l| *l as u8).unwrap_or_default();
    if vpn != Link::Off {
        icons = icons.child(icon_text(VPN_GLYPH).key("vpn").opacity(if vpn == Link::On { 1.0 } else { 0.5 }).transition(Transition::opacity()));
    }
    let mut e = slot("wifi", icons).on_press(|s: &mut Bar| toggle_panel(s));
    if !s.wifi_open { e = e.help(tooltip(d)); }
    if let Some(p) = panel(s, d) { e = e.child(p); }
    e
}

/// The tooltip, as nm-applet's item had it: the network and its signal, or why not.
fn tooltip(d: &Data) -> String {
    if d.wired.iter().any(|w| w.link == Link::On) { return "Ethernet".into(); }
    match d.wifi.networks.iter().find(|n| n.active).filter(|_| d.wifi.enabled) {
        Some(n) => format!("{} {}%", n.ssid, n.signal),
        None => "Disconnected".into(),
    }
}

fn toggle_panel(s: &mut Bar) {
    let open = !s.wifi_open;
    crate::close_popups(s);
    s.wifi_open = open;
    if open { sources::rescan_wifi(); }
}

pub fn close(s: &mut Bar) {
    s.wifi_open = false;
    s.others_open = false;
    s.vpn_open = false;
    s.vpn_slid = false;
}

/// The on/off switch: a pill whose knob springs across.
pub(crate) fn switch(on: bool) -> El {
    el().key("switch").w(32.0).h(18.0).radius(9.0).fill(if on { accent() } else { c("#ffffff").alpha(0.18) })
        .child(el().key("knob").absolute(if on { 16.0 } else { 2.0 }, 2.0).size(14.0, 14.0).radius(7.0).fill(c("#ffffff")))
}

pub(crate) fn row_base(key: &str) -> El {
    row().key(key).w_full().gap(10.0).px(6.0).py(4.0).radius(6.0).items_center()
}

fn network_row(d: &Data, n: &WifiNet) -> El {
    let joining = d.wifi.joining.as_deref() == Some(n.ssid.as_str());
    // Badge: the network's strength in a circle, filled with the accent once joined.
    let badge = el().key("badge").size(26.0, 26.0).radius(13.0).center()
        .fill(if n.active { accent() } else { c("#ffffff").alpha(0.12) })
        .child(glyph(strength_glyph(n.signal), 14.0, c("#ffffff")).key(strength_glyph(n.signal)));
    let mut r = row_base(&format!("net-{}", n.ssid)).child(badge)
        .child(text(n.ssid.clone()).key("name").font(LABEL).color(fg()).grow(1.0).truncate());
    if joining {
        r = r.child(text("Joining…").key("joining").font(LABEL).color(muted()).transition(Transition::opacity()));
    } else if n.secure {
        r = r.child(glyph("\u{f033e}", 13.0, fg()).key("lock").opacity(0.5));
    }
    let (ssid, known, active) = (n.ssid.clone(), n.known.clone(), n.active);
    // Clicking the joined network leaves it; any other joins it.
    r.hover(hover()).hit().on_press(move |_: &mut Bar| match (&known, active) {
        (Some(uuid), true) => sources::nmcli_action(ssid.clone(), vec![args(&["connection", "down", "uuid", uuid])]),
        (_, true) => {}
        _ => sources::join_wifi(ssid.clone(), known.clone()),
    })
}

fn args(a: &[&str]) -> Vec<String> { a.iter().map(|s| s.to_string()).collect() }

/// A round badge with `icon`, filled with the accent while `on`.
pub(crate) fn badge(icon: &'static str, on: bool) -> El {
    el().key("badge").size(26.0, 26.0).radius(13.0).center()
        .fill(if on { accent() } else { c("#ffffff").alpha(0.12) })
        .child(glyph(icon, 14.0, c("#ffffff")).key(icon))
}

fn link_text(link: Link) -> &'static str {
    match link { Link::On => "Connected", Link::Connecting => "Connecting…", Link::Off => "Not Connected" }
}

/// An Ethernet port with a cable in; clicking connects or disconnects it.
fn wired_row(w: &Wired, name: String) -> El {
    let (iface, link) = (w.iface.clone(), w.link);
    row_base(&format!("wired-{}", w.iface)).child(badge(WIRED_GLYPH, link == Link::On))
        .child(text(name).key("name").font(LABEL).color(fg()).grow(1.0).truncate())
        .child(text(link_text(link)).key(link_text(link)).font(LABEL).color(muted()).transition(Transition::opacity()))
        .hover(hover()).hit().on_press(move |_: &mut Bar| {
            let verb = if link == Link::Off { "connect" } else { "disconnect" };
            sources::nmcli_action(iface.clone(), vec![args(&["device", verb, &iface])]);
        })
}

/// The main page's VPN row: what's up, and a way into the VPN page.
fn vpn_status_row(d: &Data) -> El {
    let up: Vec<&str> = d.vpns.iter().filter(|v| v.link == Link::On).map(|v| v.name.as_str()).collect();
    let status = if !up.is_empty() { up.join(", ") }
        else if d.vpns.iter().any(|v| v.link == Link::Connecting) { "Connecting…".into() }
        else { "Off".into() };
    row_base("vpn").child(badge(VPN_GLYPH, !up.is_empty()))
        .child(text("VPN").key("name").font(LABEL).color(fg()).grow(1.0))
        .child(text(status.clone()).key(status.as_str()).font(LABEL).color(muted()).max_w(160.0).truncate().transition(Transition::opacity()))
        .child(glyph("\u{f0142}", 14.0, fg()).key("chevron").opacity(0.6))
        .hover(hover()).hit().on_press(|s: &mut Bar| { s.vpn_open = true; s.vpn_slid = true; })
}

/// A VPN on the VPN page. Clicking one that's down brings it up, first taking down any other
/// full-tunnel VPN (two would fight over the default route); clicking one that's up takes it down.
fn vpn_row(d: &Data, v: &Vpn) -> El {
    let (uuid, link) = (v.uuid.clone(), v.link);
    let mut steps: Vec<Vec<String>> = if link != Link::Off { vec![args(&["connection", "down", "uuid", &uuid])] } else {
        d.vpns.iter().filter(|o| v.full_tunnel && o.full_tunnel && o.link != Link::Off && o.uuid != v.uuid)
            .map(|o| args(&["connection", "down", "uuid", &o.uuid])).collect()
    };
    if link == Link::Off { steps.push(args(&["connection", "up", "uuid", &uuid])); }
    let mut r = row_base(&format!("vpn-{}", v.uuid)).child(badge(VPN_GLYPH, link == Link::On))
        .child(text(v.name.clone()).key("name").font(LABEL).color(fg()).grow(1.0).truncate());
    if link == Link::Connecting {
        r = r.child(text("Connecting…").key("connecting").font(LABEL).color(muted()).transition(Transition::opacity()));
    }
    r.hover(hover()).hit().on_press(move |_: &mut Bar| sources::nmcli_action(uuid.clone(), steps.clone()))
}

/// The VPN page: a back row, then every saved VPN.
fn vpn_page(d: &Data) -> Vec<El> {
    let mut rows = vec![
        row_base("vpn-back").py(6.0).child(glyph("\u{f004d}", 14.0, fg()).key("back").opacity(0.6))
            .child(text("VPN").key("title").font(TITLE).color(fg()))
            .hover(hover()).hit().on_press(|s: &mut Bar| { s.vpn_open = false; s.vpn_slid = true; }),
    ];
    for v in &d.vpns {
        rows.push(vpn_row(d, v));
        if let Some(e) = error_line(d, &v.uuid) { rows.push(e); }
    }
    rows
}

pub(crate) fn section(key: &str, label: &str) -> El {
    text(label).key(key).font(SMALL).color(muted()).px(6.0).pt(8.0).pb(2.0)
}

pub(crate) fn sep(key: &str) -> El { el().key(key).w_full().h(1.0).my(5.0).fill(c("#ffffff").alpha(0.1)) }

fn error_line(d: &Data, ssid: &str) -> Option<El> {
    let (failed, msg) = d.wifi.error.as_ref()?;
    (failed == ssid).then(|| text(msg.clone()).key(format!("err-{ssid}").as_str()).font(TextStyle::new(11.0, 400.0))
        .color(c("#ff6961")).px(6.0).pl(42.0).wrap().transition(Transition::opacity()))
}

fn push_network(rows: &mut Vec<El>, d: &Data, n: &WifiNet) {
    rows.push(network_row(d, n));
    if let Some(e) = error_line(d, &n.ssid) { rows.push(e); }
}

fn panel(s: &Bar, d: &Data) -> Option<El> {
    if !s.wifi_open { return None; }
    // Pages slide like a macOS submenu: the VPN page in from the right, the main one back from the left.
    // Only on a switch: a page entering with the panel would slide in as it opens.
    let page = |key: &str, edge, rows| {
        let p = col().key(key).w_full().children(rows);
        if s.vpn_slid { p.transition(Transition::move_edge(edge).combined(Transition::opacity())) } else { p }
    };
    let page = if s.vpn_open { page("page-vpn", rune::Edge::Trailing, vpn_page(d)) }
        else { page("page-main", rune::Edge::Leading, main_page(s, d)) };
    Some(panel_box(s, "wifi-panel", vec![
        page,
        sep("settings-sep"),
        row_base("settings").py(8.0).child(text("Network Settings…").key("label").font(LABEL).color(fg()))
            .hover(hover()).hit().on_press(|s: &mut Bar| { close(s); crate::spawn("nm-connection-editor", &[]); }),
    ]))
}

/// A status item's dropdown panel, hanging from the item's right edge under the bar, its
/// `rows` scrolling (with a scrollbar) when they outgrow the screen.
pub(crate) fn panel_box(s: &Bar, key: &str, rows: Vec<El>) -> El {
    panel_frame(s, key, PANEL_W, c("#1e1e1e"), 12.0, rows, None)
}

/// `panel_box` at another width, fill and corner radius (the notification list's GNOME look),
/// with a `footer` that stays put under the scrolling rows.
pub(crate) fn panel_frame(s: &Bar, key: &str, w: f32, fill: Color, radius: f32, rows: Vec<El>, footer: Option<El>) -> El {
    let frame = col().key(key).pin(None, Some(crate::BAR_H - 2.0), Some(-6.0), None).w(w)
        .max_h(crate::PANEL_H - crate::BAR_H - 12.0).radius(radius).fill(fill)
        .border(1.0, c("#ffffff").alpha(0.1)).shadow(10.0, 30.0, c("#000000").alpha(0.5)).clip_rounded(radius)
        .hit().transition(crate::popup());
    // ponytail: the scrollbar's track assumes the whole cap; a footer makes it run a little long
    crate::scroller(s, frame, w, crate::PANEL_H - crate::BAR_H - 14.0, col().key("list").padding(6.0).children(rows)).children(footer)
}

fn main_page(s: &Bar, d: &Data) -> Vec<El> {
    let w = &d.wifi;
    let mut rows = vec![
        row_base("header").py(6.0).child(text("Wi-Fi").key("title").font(TITLE).color(fg()).grow(1.0))
            .child(switch(w.enabled)).hit().on_press(|_: &mut Bar| {
                let on = crate::hub::data().wifi.enabled;
                sources::set_wifi(!on);
            }),
    ];
    if w.enabled {
        let (known, others): (Vec<&WifiNet>, Vec<&WifiNet>) = w.networks.iter().partition(|n| n.known.is_some() || n.active);
        if !known.is_empty() {
            rows.push(section("known-title", if known.len() == 1 { "Known Network" } else { "Known Networks" }));
            for n in known { push_network(&mut rows, d, n); }
        }
        let chevron = glyph("\u{f0142}", 14.0, fg()).key("chevron").rotate(if s.others_open { std::f32::consts::FRAC_PI_2 } else { 0.0 });
        rows.push(row_base("others-title").pt(8.0).child(text("Other Networks").key("label").font(SMALL).color(muted()).grow(1.0))
            .child(el().key("chevron-box").opacity(0.6).child(chevron))
            .hover(hover()).hit().on_press(|s: &mut Bar| s.others_open = !s.others_open));
        if s.others_open {
            for n in others { push_network(&mut rows, d, n); }
            // A hidden network needs its name typed: NetworkManager's own new-connection dialog.
            rows.push(row_base("other").child(el().key("pad").w(26.0)).child(text("Other…").key("label").font(LABEL).color(fg()))
                .hover(hover()).hit().on_press(|s: &mut Bar| { close(s); crate::spawn("nm-connection-editor", &["--create", "--type=802-11-wireless"]); }));
        }
    }
    if !d.wired.is_empty() {
        rows.push(sep("wired-sep"));
        rows.push(section("wired-title", "Ethernet"));
        // Name ports by interface only when there's more than one to tell apart.
        let many = d.wired.len() > 1;
        for w in &d.wired {
            rows.push(wired_row(w, if many { format!("Ethernet ({})", w.iface) } else { "Ethernet".into() }));
            if let Some(e) = error_line(d, &w.iface) { rows.push(e); }
        }
    }
    if !d.vpns.is_empty() {
        rows.push(sep("vpn-sep"));
        rows.push(vpn_status_row(d));
    }
    rows
}
