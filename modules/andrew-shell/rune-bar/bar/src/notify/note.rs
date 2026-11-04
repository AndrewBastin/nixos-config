//! A notification, and the pure helpers that turn a `Notify` call into one.
//! Ported in part from hokum (https://github.com/anomalyco/hokum, MIT): src/bus.rs, src/icons.rs.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{Duration, SystemTime};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum Timeout { #[default] Default, Never, After(Duration) }

#[derive(Clone, Debug, PartialEq)]
pub enum Picture { File(PathBuf), Rgba { width: u32, height: u32, bytes: Arc<[u8]> } }

#[derive(Clone, Debug)]
pub struct Note {
    pub id: u32,
    pub app: String,
    /// Shown after the app's name: a browser notification's site.
    pub context: Option<String>,
    pub summary: String,
    pub body: String,
    /// Buttons, (key, label), without "default".
    pub actions: Vec<(String, String)>,
    pub has_default: bool,
    /// 0 low, 1 normal, 2 critical.
    pub urgency: u8,
    /// The `value` hint, 0..=1: a progress bar.
    pub value: Option<f32>,
    /// A stack tag: a later notification with the same tag and app replaces this one.
    pub tag: Option<String>,
    pub resident: bool,
    pub transient: bool,
    pub timeout: Timeout,
    pub time: SystemTime,
    pub icon: Option<Picture>,
    pub image: Option<Picture>,
    /// `icon` and `image`, decoded (off the UI thread) for drawing.
    pub icon_img: Option<rune::Image>,
    pub image_img: Option<rune::Image>,
}

impl Note {
    pub fn new(id: u32, app: &str, summary: &str, body: &str) -> Note {
        Note {
            id, app: app.into(), context: None, summary: summary.into(), body: body.into(),
            actions: Vec::new(), has_default: false, urgency: 1, value: None, tag: None,
            resident: false, transient: false, timeout: Timeout::Default, time: SystemTime::now(),
            icon: None, image: None, icon_img: None, image_img: None,
        }
    }
}

/// Bodies may carry the spec's small markup subset; cards show plain text, capped at 280
/// characters. A `<` is a tag only when a `>` closes it before the next `<` or line end, so
/// "I <3 you" survives; `<br>` is a line break.
pub fn plain(body: &str) -> String {
    let mut out = String::with_capacity(body.len());
    let mut rest = body;
    while let Some(i) = rest.find('<') {
        out.push_str(&rest[..i]);
        let after = &rest[i + 1..];
        match after.find(['>', '<', '\n']).filter(|&j| after.as_bytes()[j] == b'>') {
            Some(j) => {
                if after[..j].trim().trim_end_matches('/').trim().eq_ignore_ascii_case("br") { out.push('\n'); }
                rest = &after[j + 1..];
            }
            None => { out.push('<'); rest = after; }
        }
    }
    out.push_str(rest);
    let out = entities(&out);
    let out = out.trim();
    match out.char_indices().nth(280) {
        Some((i, _)) => format!("{}…", out[..i].trim_end()),
        None => out.to_owned(),
    }
}

/// The named entities markup uses, and numeric ones; anything else stays as written.
fn entities(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        let after = &rest[i + 1..];
        let decoded = after.find(';').filter(|&j| j <= 10).and_then(|j| {
            let name = &after[..j];
            let ch = match name {
                "lt" => Some('<'), "gt" => Some('>'), "amp" => Some('&'), "quot" => Some('"'), "apos" => Some('\''), "nbsp" => Some(' '),
                _ => match name.strip_prefix('#') {
                    Some(n) => match n.strip_prefix(['x', 'X']) {
                        Some(hex) => u32::from_str_radix(hex, 16).ok(),
                        None => n.parse().ok(),
                    }.and_then(char::from_u32),
                    None => None,
                },
            };
            ch.map(|c| (c, j))
        });
        match decoded {
            Some((c, j)) => { out.push(c); rest = &after[j + 1..]; }
            None => { out.push('&'); rest = after; }
        }
    }
    out.push_str(rest);
    out
}

/// Splits Notify's flat `[key, label, …]` into whether there's a default action and the
/// buttons. Chromium's per-site "settings" button is dropped, as KDE does.
pub fn split_actions(actions: &[String]) -> (bool, Vec<(String, String)>) {
    let mut has_default = false;
    let mut buttons = Vec::new();
    for pair in actions.chunks(2) {
        match (pair[0].as_str(), pair.get(1)) {
            ("default", _) => has_default = true,
            ("settings", _) => {}
            (key, Some(label)) if !label.is_empty() => buttons.push((key.to_owned(), label.clone())),
            _ => {}
        }
    }
    (has_default, buttons)
}

/// The ID a Notify call gets: `replaces_id` when it names one, else the next unused. Counting
/// past a named ID (one from before the bar started) keeps later IDs from colliding with it.
pub fn assign(next: &AtomicU32, replaces_id: u32) -> u32 {
    if replaces_id == 0 { return next.fetch_add(1, Ordering::Relaxed); }
    next.fetch_max(replaces_id.saturating_add(1), Ordering::Relaxed);
    replaces_id
}

/// The spec's `image-data` (`(iiibiiay)`) as RGBA8. Anything that doesn't add up (sizes over
/// 4096, short data, samples other than 8-bit RGB/RGBA) is refused rather than guessed at.
pub fn image_data(width: i32, height: i32, stride: i32, alpha: bool, bits: i32, channels: i32, data: &[u8]) -> Option<Picture> {
    let positive = |v: i32| usize::try_from(v).ok().filter(|v| *v > 0);
    let (w, h, stride, channels) = (positive(width)?, positive(height)?, positive(stride)?, positive(channels)?);
    if bits != 8 || w > 4096 || h > 4096 || !(3..=4).contains(&channels) || (alpha && channels != 4) { return None; }
    let row = w.checked_mul(channels)?;
    if stride < row || data.len() < stride.checked_mul(h - 1)?.checked_add(row)? { return None; }
    let mut out = Vec::with_capacity(w * h * 4);
    for y in 0..h {
        for px in data.get(y * stride..y * stride + row)?.chunks_exact(channels) {
            out.extend_from_slice(&[px[0], px[1], px[2], if channels == 4 { px[3] } else { 255 }]);
        }
    }
    Some(Picture::Rgba { width: w as u32, height: h as u32, bytes: out.into() })
}

/// How long `n`'s card stays up; `None` until dismissed. Low 4 s, normal 6 s (10 s with
/// buttons, to reach them), critical never; the app's own timeout wins.
pub fn default_timeout(n: &Note) -> Option<Duration> {
    match n.timeout {
        Timeout::Never => None,
        Timeout::After(d) => Some(d),
        Timeout::Default => match n.urgency {
            2.. => None,
            0 => Some(Duration::from_secs(4)),
            _ if !n.actions.is_empty() => Some(Duration::from_secs(10)),
            _ => Some(Duration::from_secs(6)),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_strips_markup_and_caps_length() {
        assert_eq!(plain("<b>Hi</b> &amp; <a href=\"x\">you</a>"), "Hi & you");
        assert_eq!(plain(&"x".repeat(10_000)).chars().count(), 281);
        assert_eq!(plain("  a  "), "a");
    }

    #[test]
    fn plain_keeps_stray_angle_brackets_and_decodes_entities() {
        assert_eq!(plain("I <3 you"), "I <3 you");
        assert_eq!(plain("a < b, see log"), "a < b, see log");
        assert_eq!(plain("it&#8217;s &#x27;ok&#x27;&nbsp;now"), "it\u{2019}s 'ok' now");
        assert_eq!(plain("one<br>two<br/>three"), "one\ntwo\nthree");
        assert_eq!(plain("x &lt;b&gt; y"), "x <b> y");
    }

    #[test]
    fn split_actions_finds_default_and_drops_settings() {
        let a = ["default", "Open", "settings", "Settings", "reply", "Reply"].map(String::from);
        assert_eq!(split_actions(&a), (true, vec![("reply".into(), "Reply".into())]));
        let odd = ["reply", "Reply", "dangling"].map(String::from);
        assert_eq!(split_actions(&odd), (false, vec![("reply".into(), "Reply".into())]));
    }

    #[test]
    fn assign_counts_past_foreign_ids() {
        let next = AtomicU32::new(1);
        assert_eq!(assign(&next, 0), 1);
        assert_eq!(assign(&next, 50), 50);
        assert_eq!(assign(&next, 0), 51);
    }

    #[test]
    fn image_data_rejects_bad_sizes() {
        let rgba = [7u8; 16];
        assert!(matches!(image_data(2, 2, 8, true, 8, 4, &rgba), Some(Picture::Rgba { width: 2, height: 2, .. })));
        assert_eq!(image_data(2, 2, 8, true, 8, 4, &rgba[..15]), None);
        assert_eq!(image_data(100_000, 1, 400_000, true, 8, 4, &rgba), None);
        let Some(Picture::Rgba { bytes, .. }) = image_data(1, 1, 3, false, 8, 3, &[1, 2, 3]) else { panic!() };
        assert_eq!(*bytes, [1, 2, 3, 255]);
    }

    #[test]
    fn default_timeouts_follow_urgency() {
        let mut n = Note::new(1, "a", "s", "");
        assert_eq!(default_timeout(&n), Some(Duration::from_secs(6)));
        n.actions.push(("r".into(), "R".into()));
        assert_eq!(default_timeout(&n), Some(Duration::from_secs(10)));
        n.actions.clear();
        n.urgency = 0;
        assert_eq!(default_timeout(&n), Some(Duration::from_secs(4)));
        n.urgency = 2;
        assert_eq!(default_timeout(&n), None);
        n.urgency = 1;
        n.timeout = Timeout::After(Duration::from_secs(2));
        assert_eq!(default_timeout(&n), Some(Duration::from_secs(2)));
        n.timeout = Timeout::Never;
        assert_eq!(default_timeout(&n), None);
    }
}
