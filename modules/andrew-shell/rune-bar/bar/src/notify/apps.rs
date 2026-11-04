//! Which app sent a notification, and its icon, from the installed desktop entries; a
//! browser's notification from an installed web app shows as that app.
//! Ported in part from hokum (https://github.com/anomalyco/hokum, MIT): src/entries.rs, src/bus.rs.

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Entry {
    /// The desktop file ID without `.desktop`.
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub wm_class: Option<String>,
    /// `Categories=` has `WebBrowser`.
    pub browser: bool,
    /// The site a web-app launcher opens (`--app=https://web.whatsapp.com/` → `web.whatsapp.com`).
    pub site: Option<String>,
}

#[derive(Debug, Default, PartialEq)]
pub struct Who {
    pub app: String,
    /// The desktop entry found for it.
    pub entry: Option<String>,
    pub icon: Option<PathBuf>,
    /// For a browser notification from a site that isn't an installed web app: the site.
    pub context: Option<String>,
    /// The body without a browser's site line.
    pub body: String,
}

/// Reads a desktop entry's `[Desktop Entry]` group; `None` for anything that isn't an
/// application, or is `Hidden=true` (deleted).
pub fn parse(id: &str, text: &str) -> Option<Entry> {
    let mut e = Entry { id: id.to_owned(), ..Entry::default() };
    let mut inside = false;
    for line in text.lines().map(str::trim) {
        if line.starts_with('[') { inside = line == "[Desktop Entry]"; continue; }
        let Some((key, value)) = line.split_once('=').filter(|_| inside) else { continue };
        let value = value.trim();
        match key.trim() {
            "Type" if value != "Application" => return None,
            "Hidden" if value == "true" => return None,
            "Name" => e.name = value.to_owned(),
            "Icon" if !value.is_empty() => e.icon = Some(value.to_owned()),
            "StartupWMClass" if !value.is_empty() => e.wm_class = Some(value.to_owned()),
            "Categories" => e.browser = value.split(';').any(|c| c == "WebBrowser"),
            "Exec" => e.site = value.split_whitespace().find_map(|w| site(w.strip_prefix("--app=")?)),
            _ => {}
        }
    }
    Some(e)
}

/// The host of an http(s) URL, lowercased, without `www.`.
fn site(url: &str) -> Option<String> {
    let rest = url.trim().strip_prefix("https://").or_else(|| url.trim().strip_prefix("http://"))?;
    let host = rest.split(['/', '?', '#']).next()?.rsplit('@').next()?.split(':').next()?.to_lowercase();
    let host = host.strip_prefix("www.").unwrap_or(&host).to_owned();
    (host.contains('.') && !host.contains(char::is_whitespace)).then_some(host)
}

fn same(a: &str, b: &str) -> bool { a.to_lowercase() == b.to_lowercase() }

/// `Name=` without a trailing `(…)`, as betas and AppImages add.
fn bare(name: &str) -> &str {
    match name.trim_end().strip_suffix(')').and_then(|n| n.rfind(" (").map(|i| &name[..i])) {
        Some(b) if !b.trim().is_empty() => b.trim(),
        _ => name.trim(),
    }
}

fn by_id<'a>(entries: &'a [Entry], id: &str) -> Option<&'a Entry> {
    let id = id.strip_suffix(".desktop").unwrap_or(id);
    entries.iter().find(|e| e.id == id).or_else(|| entries.iter().find(|e| same(&e.id, id)))
}

fn by_name<'a>(entries: &'a [Entry], app: &str) -> Option<&'a Entry> {
    let app = app.trim();
    if app.is_empty() { return None; }
    by_id(entries, app)
        .or_else(|| entries.iter().find(|e| e.wm_class.as_deref().is_some_and(|w| same(w, app))))
        .or_else(|| entries.iter().find(|e| e.site.is_none() && (same(&e.name, app) || same(bare(&e.name), app))))
        .or_else(|| by_id(entries, &app.to_lowercase().replace(' ', "-")))
}

/// Chromium-family browsers start a web notification's body with its site (a link, or text),
/// then a blank line. The site, and the body after it.
fn web_site(body: &str) -> Option<(String, &str)> {
    let (first, rest) = body.split_once('\n').unwrap_or((body, ""));
    let first = first.trim();
    let site = match first.strip_prefix("<a href=\"") {
        Some(link) => {
            let (url, text) = link.split_once("\">")?;
            text.strip_suffix("</a>")?;
            site(url)?
        }
        // As text, only with a message after it: a body that is just a domain is a message.
        None if first.contains(['<', ' ', '/']) || rest.is_empty() => return None,
        None => site(&format!("https://{first}"))?,
    };
    let rest = if rest.is_empty() { rest } else { rest.strip_prefix('\n').or_else(|| rest.strip_prefix("\r\n"))? };
    Some((site, rest))
}

/// A theme icon's name or a path, as a file.
fn resolve(icon: &str) -> Option<PathBuf> {
    let icon = icon.strip_prefix("file://").unwrap_or(icon).trim();
    if icon.is_empty() { return None; }
    crate::sources::icon_path(icon, None)
}

/// Finds the app behind a notification and its icon: a browser's site that is an installed
/// web app; the icon the notification names; its `desktop-entry`; its name; an icon called
/// like it.
// ponytail: no sandbox/launcher clues; add hokum's sender.rs if Flatpak apps show as "Notification"
pub fn identify(entries: &[Entry], app: &str, app_icon: &str, desktop: Option<&str>, body: &str, launcher: &[String]) -> Who {
    // Most specific first; the program that sent it last (Zen sends "Zen"/"zen" but launches
    // as zen-beta). The first names the app; the first with an icon draws it.
    let candidates: Vec<&Entry> = [desktop.and_then(|d| by_id(entries, d)), by_name(entries, app)].into_iter()
        .chain(launcher.iter().map(|n| by_name(entries, n))).flatten().collect();
    let named = candidates.first().copied();
    let mut who = Who { app: app.to_owned(), entry: named.map(|e| e.id.clone()), body: body.to_owned(), ..Who::default() };
    if named.is_some_and(|e| e.browser) && let Some((site, rest)) = web_site(body) {
        who.body = rest.to_owned();
        if let Some(web) = entries.iter().find(|e| e.site.as_deref() == Some(site.as_str())) {
            who.app = bare(&web.name).to_owned();
            who.icon = web.icon.as_deref().and_then(resolve);
            return who;
        }
        who.context = Some(site);
    }
    if let Some(e) = named {
        // An app that sends its ID for a name (Flatpaks through the portal) reads as its name.
        if (same(app, &e.id) || app.trim().is_empty()) && !e.name.trim().is_empty() { who.app = bare(&e.name).to_owned(); }
    }
    who.icon = resolve(app_icon)
        .or_else(|| candidates.iter().find_map(|e| e.icon.as_deref().and_then(resolve)))
        .or_else(|| resolve(&app.trim().to_lowercase().replace(' ', "-")));
    who
}

/// What the sending process calls itself, from its command line (NUL-separated): the program
/// it was started as, without NixOS's `.…-wrapped`, and any `--class`/`--name` it was given.
pub fn launcher_names(cmdline: &[u8]) -> Vec<String> {
    let args: Vec<String> = cmdline.split(|b| *b == 0).filter(|a| !a.is_empty()).map(|a| String::from_utf8_lossy(a).into_owned()).collect();
    let mut names: Vec<String> = Vec::new();
    let mut push = |n: &str| if !n.is_empty() && !names.iter().any(|m| m == n) { names.push(n.to_owned()) };
    if let Some(program) = args.first() {
        let base = program.rsplit('/').next().unwrap_or(program);
        let base = base.strip_prefix('.').and_then(|b| b.strip_suffix("-wrapped")).unwrap_or(base);
        push(base);
    }
    for (i, a) in args.iter().enumerate() {
        for flag in ["--class", "--name"] {
            match a.strip_prefix(flag) {
                Some(v) if v.starts_with('=') => push(&v[1..]),
                Some("") => if let Some(v) = args.get(i + 1) { push(v) },
                _ => {}
            }
        }
    }
    names
}

/// The installed desktop entries, scanned once.
// ponytail: scanned once per bar run; rescan on an applications/ change if new apps show unnamed
pub fn entries() -> Arc<Vec<Entry>> {
    static ENTRIES: OnceLock<Arc<Vec<Entry>>> = OnceLock::new();
    ENTRIES.get_or_init(|| {
        let mut dirs: Vec<PathBuf> = std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")).into_iter().collect();
        let data = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/share".into());
        dirs.extend(data.split(':').filter(|d| !d.is_empty()).map(PathBuf::from));
        let mut out: Vec<Entry> = Vec::new();
        for dir in dirs { scan(&dir.join("applications"), "", &mut out); }
        Arc::new(out)
    }).clone()
}

/// Earlier directories win, as the spec's lookup order has it.
fn scan(dir: &std::path::Path, prefix: &str, out: &mut Vec<Entry>) {
    let Ok(read) = std::fs::read_dir(dir) else { return };
    for f in read.flatten() {
        let path = f.path();
        let name = f.file_name().to_string_lossy().into_owned();
        if path.is_dir() { scan(&path, &format!("{prefix}{name}-"), out); continue; }
        let Some(stem) = name.strip_suffix(".desktop") else { continue };
        let id = format!("{prefix}{stem}");
        if out.iter().any(|e| e.id == id) { continue; }
        if let Some(e) = std::fs::read_to_string(&path).ok().and_then(|t| parse(&id, &t)) { out.push(e); }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn e(id: &str, text: &str) -> Entry { parse(id, &format!("[Desktop Entry]\nType=Application\n{text}")).unwrap() }

    #[test]
    fn parse_reads_name_icon_and_web_app_site() {
        let w = e("chrome-abc-Default", "Name=WhatsApp\nIcon=chrome-abc-Default\nExec=chromium --profile-directory=Default --app=https://web.whatsapp.com/");
        assert_eq!((w.name.as_str(), w.icon.as_deref(), w.site.as_deref()), ("WhatsApp", Some("chrome-abc-Default"), Some("web.whatsapp.com")));
        assert!(e("chromium", "Name=Chromium\nCategories=Network;WebBrowser;").browser);
        assert_eq!(parse("x", "[Desktop Entry]\nType=Link\nName=X"), None);
        assert_eq!(parse("x", "[Desktop Entry]\nName=X\nHidden=true"), None);
    }

    #[test]
    fn identify_prefers_named_icon_then_desktop_entry_then_name() {
        let es = vec![e("org.gnome.Nautilus", "Name=Files\nIcon=/abs/nautilus.svg"), e("slack", "Name=Slack\nStartupWMClass=Slack\nIcon=/abs/slack.svg")];
        let w = identify(&es, "notify-send", "/abs/given.png", None, "b", &[]);
        assert_eq!(w.icon, Some(PathBuf::from("/abs/given.png")).filter(|p| p.exists()));
        let w = identify(&es, "org.gnome.Nautilus", "", Some("org.gnome.Nautilus"), "b", &[]);
        assert_eq!(w.app, "Files");
        let w = identify(&es, "Slack", "", None, "b", &[]);
        assert_eq!((w.app.as_str(), w.body.as_str()), ("Slack", "b"));
    }

    #[test]
    fn browser_notification_from_installed_web_app_shows_as_that_app() {
        let es = vec![
            e("chromium-browser", "Name=Chromium\nCategories=WebBrowser;"),
            e("chrome-abc-Default", "Name=WhatsApp\nExec=chromium --app=https://web.whatsapp.com/"),
        ];
        let w = identify(&es, "Chromium", "", None, "web.whatsapp.com\n\nHi", &[]);
        assert_eq!((w.app.as_str(), w.body.as_str(), w.context), ("WhatsApp", "Hi", None));
        let w = identify(&es, "Chromium", "", None, "<a href=\"https://web.whatsapp.com/\">web.whatsapp.com</a>\n\nHi", &[]);
        assert_eq!(w.app, "WhatsApp");
    }

    #[test]
    fn unknown_site_becomes_context() {
        let es = vec![e("chromium-browser", "Name=Chromium\nCategories=WebBrowser;")];
        let w = identify(&es, "Chromium", "", None, "github.com\n\nPR merged", &[]);
        assert_eq!((w.app.as_str(), w.body.as_str(), w.context.as_deref()), ("Chromium", "PR merged", Some("github.com")));
        // A body that is just a domain is a message.
        assert_eq!(identify(&es, "Chromium", "", None, "github.com", &[]).body, "github.com");
    }

    #[test]
    fn launcher_names_read_program_and_class() {
        assert_eq!(launcher_names(b"/etc/profiles/per-user/a/bin/zen-beta\0--name=zen-beta\0--class=zen-beta\0"), vec!["zen-beta".to_owned()]);
        assert_eq!(launcher_names(b"/nix/store/x/bin/.slack-wrapped\0--class\0Slack\0"), vec!["slack".to_owned(), "Slack".to_owned()]);
        assert!(launcher_names(b"").is_empty());
    }

    #[test]
    fn unmatched_name_falls_back_to_the_senders_program() {
        // Zen sends app "Zen" and desktop-entry "zen"; its launcher is zen-beta.desktop.
        let es = vec![e("zen-beta", "Name=Zen Browser (Beta)\nStartupWMClass=zen-beta\nIcon=zen-browser\nExec=zen-beta --name zen-beta %U")];
        let w = identify(&es, "Zen", "", Some("zen"), "b", &["zen-beta".to_owned()]);
        assert_eq!((w.app.as_str(), w.entry.as_deref()), ("Zen", Some("zen-beta")));
        assert_eq!(identify(&es, "Zen", "", Some("zen"), "b", &[]).entry, None);
    }

    #[test]
    fn an_iconless_match_names_the_app_and_a_later_one_draws_it() {
        // A file-association entry named "Zen" (no icon) matches first; zen-beta's icon draws.
        let icon = std::env::temp_dir().join("andrew-bar-test-zen.png");
        std::fs::write(&icon, b"x").unwrap();
        let es = vec![
            e("userapp-Zen-QR59E3", "Name=Zen\nNoDisplay=true\nExec=/nix/store/x/zen %u"),
            e("zen-beta", &format!("Name=Zen Browser (Beta)\nIcon={}\nExec=zen-beta %U", icon.display())),
        ];
        let w = identify(&es, "Zen", "", Some("zen"), "b", &["zen-beta".to_owned()]);
        assert_eq!((w.entry.as_deref(), w.icon), (Some("userapp-Zen-QR59E3"), Some(icon)));
    }
}
