//! The clock's Calendar panel, after macOS's calendar widget: this month's grid with today
//! marked, then the coming events by day (Thunderbird's, via `calendar-status`), each with a
//! Join button when it has a meeting link.

use rune::{El, TextStyle, col, el, row, text};

use crate::clock::{self, local};
use crate::sources::Event;
use crate::wifi::{TITLE, muted, panel_box, row_base, section, sep};
use crate::{Bar, Data, LABEL, accent, c, fg, hover, spawn};

const SMALL: TextStyle = TextStyle::new(11.0, 400.0);
const WEEKDAYS: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS: [&str; 12] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

pub fn toggle_panel(s: &mut Bar) {
    let open = !s.calendar_open;
    crate::close_popups(s);
    s.calendar_open = open;
}

pub fn close(s: &mut Bar) { s.calendar_open = false; }

/// The clock, opening the panel.
pub fn clock(s: &Bar, d: &Data) -> El {
    let mut e = el().key("clock").px(4.0).py(5.0).mx(-4.0).my(-3.0).radius(4.0).hover(hover()).hit().center()
        .child(text(clock::date_time(d.now)).key("time").font(LABEL).color(fg()))
        .on_press(|s: &mut Bar| toggle_panel(s));
    if let Some(p) = panel(s, d) { e = e.child(p); }
    e
}

fn days_in_month(year: i32, month0: i32) -> i32 {
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month0 as usize % 12]
}

/// This month as a Sunday-first grid, today in the accent circle.
fn month(now: i64) -> El {
    let tm = local(now);
    let first = (tm.tm_wday - (tm.tm_mday - 1)).rem_euclid(7);
    let days = days_in_month(tm.tm_year + 1900, tm.tm_mon);
    let cell = |key: String, child: El| el().key(key.as_str()).w_frac(1.0 / 7.0).h(26.0).center().child(child);
    let mut grid = col().key("grid").w_full().px(10.0).gap(1.0).child(
        row().key("weekdays").w_full().children(["S", "M", "T", "W", "T", "F", "S"].iter().enumerate()
            .map(|(i, l)| cell(format!("wd{i}"), text(*l).key("l").font(SMALL).color(muted())))));
    let mut day = 1 - first;
    while day <= days {
        let week = (1..=7).map(|i| {
            let n = day + i - 1;
            let label = if (1..=days).contains(&n) { n.to_string() } else { String::new() };
            let today = n == tm.tm_mday;
            cell(format!("d{i}"), el().key("dot").size(22.0, 22.0).radius(11.0).center()
                .fill(if today { accent() } else { c("#000000").alpha(0.0) })
                .child(text(label).key("n").font(SMALL).color(if today { c("#ffffff") } else { fg() })))
        });
        grid = grid.child(row().key(format!("w{day}").as_str()).w_full().children(week));
        day += 7;
    }
    col().key("month").w_full().gap(4.0)
        .child(row_base("month-title").child(text(format!("{} {}", MONTHS[tm.tm_mon as usize % 12], tm.tm_year + 1900)).key("t").font(TITLE).color(fg())))
        .child(grid)
}

/// A calendar's colour: Thunderbird keeps its own in prefs; a stable pick from a palette will do.
fn color(calendar: &str) -> rune::Color {
    // ponytail: hashed palette, read calendar.registry.<id>.color from prefs.js if it should match Thunderbird.
    const PALETTE: [&str; 6] = ["#4a9eff", "#ff9f43", "#2ed573", "#a55eea", "#ff6b81", "#1dd1a1"];
    let h = calendar.bytes().fold(0u32, |h, b| h.wrapping_mul(31).wrapping_add(b as u32));
    c(PALETTE[h as usize % PALETTE.len()])
}

/// One event; `weekday` prefixes its time with the day, for events past tomorrow.
fn event_row(e: &Event, weekday: bool) -> El {
    let mut when = if e.end > e.start { format!("{} – {}", clock::time(e.start), clock::time(e.end)) } else { clock::time(e.start) };
    if weekday { when = format!("{} {when}", WEEKDAYS[local(e.start).tm_wday as usize % 7]); }
    let mut r = row_base(&format!("ev-{}-{}", e.start, e.title)).gap(9.0)
        .child(el().key("bar").w(3.0).h(32.0).radius(1.5).fill(color(&e.calendar)))
        .child(col().key("text").grow(1.0).gap(2.0).min_w(0.0)
            .child(text(e.title.clone()).key("title").font(LABEL).color(fg()).truncate())
            .child(text(when).key("when").font(SMALL).color(muted()).truncate()));
    if let Some(url) = e.url.clone() {
        r = r.child(el().key("join").px(10.0).py(4.0).radius(10.0).fill(accent()).hover(c("#ffffff").alpha(0.12)).hit()
            .child(text("Join").key("l").font(SMALL).color(c("#ffffff")))
            .on_press(move |s: &mut Bar| { close(s); spawn("xdg-open", &[&url]); }));
    }
    r.hover(hover()).hit().on_press(|s: &mut Bar| { close(s); spawn("hyprctl", &["dispatch", "exec", crate::CALENDAR_APP]); })
}

fn panel(s: &Bar, d: &Data) -> Option<El> {
    if !s.calendar_open { return None; }
    let mut rows = vec![month(d.now), sep("events-sep")];
    let today = local(d.now);
    let day_of = |t: i64| { let tm = local(t); (tm.tm_year, tm.tm_yday) };
    // Earlier today, under way, later today, tomorrow, then the rest of the week (to
    // Saturday, as the grid's rows).
    const SECTIONS: [&str; 5] = ["Earlier Today", "Now", "Later Today", "Tomorrow", "This Week"];
    let (now_day, next_day) = ((today.tm_year, today.tm_yday), day_of(d.now + 86_400));
    // ponytail: a fixed 86400 s per day, an hour off across a DST change.
    let midnight = d.now - (today.tm_hour * 3600 + today.tm_min * 60 + today.tm_sec) as i64;
    let week_end = midnight + (7 - today.tm_wday) as i64 * 86_400;
    let mut buckets: [Vec<&Event>; 5] = Default::default();
    for e in d.events.iter().filter(|e| e.start >= midnight && e.start < week_end) {
        let day = day_of(e.start);
        let i = if e.start <= d.now { if e.end > d.now { 1 } else { 0 } }
            else if day == now_day { 2 } else if day == next_day { 3 } else { 4 };
        buckets[i].push(e);
    }
    for (i, events) in buckets.iter().enumerate().filter(|(_, b)| !b.is_empty()) {
        rows.push(section(&format!("sec-{i}"), SECTIONS[i]));
        // Past events dimmed, as macOS's widget.
        rows.extend(events.iter().map(|e| event_row(e, i == 4).opacity(if i == 0 { 0.5 } else { 1.0 })));
    }
    if buckets.iter().all(Vec::is_empty) {
        rows.push(row_base("none").child(text("No events this week").key("l").font(LABEL).color(muted())));
    }
    rows.push(sep("open-sep"));
    rows.push(row_base("open").py(8.0).child(text("Open Calendar…").key("l").font(LABEL).color(fg()))
        .hover(hover()).hit().on_press(|s: &mut Bar| { close(s); spawn("hyprctl", &["dispatch", "exec", crate::CALENDAR_APP]); }));
    Some(panel_box(s, "calendar-panel", rows))
}
