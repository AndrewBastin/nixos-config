//! The bell and its panel: Android's notification list (no quick settings), grouped by app,
//! with a Silent section, a Do Not Disturb switch and Clear all.

use rune::{El, Transition, col, el, row, text};

use super::cards::{CAPTION, HEADING, TITLE_2, TITLE_3, accent, button, button_hover, card, dim, lower_in_stack, popover, round_button, second_in_stack};
use crate::wifi::{panel_frame, row_base};
use crate::{Bar, Data, c, fg, glyph, icon_text, slot};

/// The bell: Do Not Disturb, notifications waiting, or none. Click opens the list;
/// right-click toggles Do Not Disturb.
pub fn status(s: &Bar, d: &Data) -> El {
    let n = &d.notify;
    let g = if n.dnd { "\u{f009b}" } else if !n.is_empty() { "\u{f116b}" } else { "\u{f0f3}" };
    let mut e = slot("notifications", icon_text(g).key(g).transition(Transition::blur_replace()))
        .on_press(|s: &mut Bar| toggle(s))
        .on_secondary_press(|_: &mut Bar, _, _| toggle_dnd());
    if s.notify_open { e = e.child(panel(s, d)); }
    e
}

fn toggle(s: &mut Bar) {
    let open = !s.notify_open;
    crate::close_popups(s);
    s.notify_open = open;
}

fn toggle_dnd() { super::with(|st, _| { st.set_dnd(!st.dnd); Vec::new() }); }

pub fn close(s: &mut Bar) {
    s.notify_open = false;
    s.notify_expanded.clear();
}

/// GNOME's list width (29em at its 11pt text, scaled to the bar's 13).
const LIST_W: f32 = 380.0;

/// A notification group as GNOME's `.message-notification-group`: one card alone; several
/// collapsed into a stack (the newest, the next two peeking under it), which a click expands
/// to a header (app name, collapse button) over every card.
fn group(s: &Bar, app: &str, notes: &[&super::note::Note]) -> El {
    let key = format!("group-{app}");
    if notes.len() == 1 { return col().key(key).w_full().child(card::<Bar>(notes[0], true)); }
    if s.notify_expanded.contains(app) {
        let a = app.to_owned();
        let header = row().key("head").w_full().padding(6.0).items_center()
            .child(text(app.to_owned()).key("title").font(TITLE_2).color(fg()).mx(4.0).grow(1.0).truncate())
            .child(round_button("collapse", "\u{f0143}", 32.0, c("#ffffff").alpha(0.2), c("#ffffff").alpha(0.3))
                .on_press(move |s: &mut Bar| { s.notify_expanded.remove(&a); }));
        return col().key(key).w_full().gap(12.0).child(header).children(notes.iter().map(|n| card::<Bar>(n, true)));
    }
    // Collapsed: the cards under the newest show as two darker strips below it.
    let peeks = notes.len().min(3) - 1;
    let mut stack = col().key(key).w_full().items_center().child(card::<Bar>(notes[0], true));
    for (i, fill) in [second_in_stack(), lower_in_stack()].into_iter().take(peeks).enumerate() {
        let inset = 12.0 * (i + 1) as f32;
        stack = stack.child(el().key(format!("peek-{i}")).h(10.0).w_full().px(inset)
            .child(el().key("strip").w_full().h_full().fill(fill).clip_corners([0.0, 0.0, 12.0, 12.0])));
    }
    let a = app.to_owned();
    // Over the whole stack, so any click on it expands the group, as GNOME's does.
    stack.child(el().key("expand").pin(Some(0.0), Some(0.0), Some(0.0), Some(0.0)).hit()
        .on_press(move |s: &mut Bar| { s.notify_expanded.insert(a.clone()); }))
}

/// GNOME's switch: 46 wide, a 20 pt handle 3 pt in, the accent when on.
fn gnome_switch(on: bool) -> El {
    el().key("switch").w(46.0).h(26.0).radius(13.0).fill(if on { accent() } else { c("#ffffff").alpha(0.15) })
        .child(el().key("handle").absolute(if on { 23.0 } else { 3.0 }, 3.0).size(20.0, 20.0).radius(10.0).fill(c("#d7d7d8"))
            .shadow(2.0, 4.0, c("#000000").alpha(0.2)))
}

fn panel(s: &Bar, d: &Data) -> El {
    let n = &d.notify;
    let mut rows = Vec::new();
    let groups = n.groups();
    let silent = n.silent();
    if groups.is_empty() && silent.is_empty() {
        // `.message-list-placeholder`.
        rows.push(col().key("empty").w_full().py(36.0).items_center().gap(12.0)
            .child(glyph("\u{f0f3}", 72.0, c("#ffffff").alpha(0.45)).key("bell"))
            .child(text("No Notifications").key("label").font(TITLE_3).color(c("#ffffff").alpha(0.45))));
    }
    let mut list = col().key("messages").w_full().gap(12.0).px(6.0).pt(6.0);
    for (app, notes) in &groups { list = list.child(group(s, app, notes)); }
    if !silent.is_empty() {
        list = list.child(text("Silent").key("silent-title").font(TITLE_2).color(fg()).mx(10.0).mt(6.0));
        list = list.children(silent.iter().map(|n| card::<Bar>(n, true)));
    }
    rows.push(list);
    if !n.owned {
        rows.push(row_base("not-serving").pt(10.0).child(text("Another notification daemon is running").key("label").font(CAPTION).color(dim())));
    }
    // `.message-list-controls`: Do Not Disturb, and Clear as a pill on the right.
    let mut controls = row().key("controls").w_full().padding(12.0).pb(9.0).gap(6.0).items_center()
        .child(row().key("dnd").gap(12.0).items_center().hit().on_press(|_: &mut Bar| toggle_dnd())
            .child(text("Do Not Disturb").key("label").font(HEADING).color(fg()))
            .child(gnome_switch(n.dnd)))
        .child(el().key("spacer").grow(1.0));
    if !n.is_empty() {
        controls = controls.child(el().key("clear").px(16.0).py(6.0).radius(999.0).fill(button()).hover(button_hover()).hit()
            .on_press(|_: &mut Bar| super::with(|st, _| st.clear()))
            .child(text("Clear").key("label").font(HEADING).color(fg())));
    }
    panel_frame(s, "notify-panel", LIST_W, popover(), 12.0, rows, Some(controls))
}
