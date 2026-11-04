//! The `org.freedesktop.Notifications` server, on a thread of its own.
//! Ported in part from hokum (https://github.com/anomalyco/hokum, MIT): src/bus.rs.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::AtomicU32;
use std::time::Duration;

use zbus::OwnedVariant as OwnedValue;

use super::apps;
use super::note::{assign, image_data, plain, split_actions, Note, Picture, Timeout};

fn hint<T: TryFrom<OwnedValue>>(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<T> {
    hints.get(key).and_then(|v| v.try_clone().ok()).and_then(|v| T::try_from(v).ok())
}

/// A Notify call, as `build` turns it into a `Note`.
pub(crate) struct Request {
    pub id: u32,
    pub app_name: String,
    pub app_icon: String,
    pub summary: String,
    pub body: String,
    pub actions: Vec<String>,
    pub hints: HashMap<String, OwnedValue>,
    pub expire_timeout: i32,
}

/// An `image-path` hint or a picture's path, as an existing file.
fn picture_file(path: &str) -> Option<PathBuf> {
    let path = PathBuf::from(path.strip_prefix("file://").unwrap_or(path));
    (path.is_absolute() && path.is_file()).then_some(path)
}

/// The `Note` a Notify call asks for. Reads files and decodes pictures: off the bus executor.
pub(crate) fn build(r: Request) -> Note {
    let Request { id, app_name, app_icon, summary, body, actions, hints, expire_timeout } = r;
    let desktop = hint::<String>(&hints, "desktop-entry").filter(|d| !d.is_empty());
    let app = Some(app_name.trim().to_owned()).filter(|a| !a.is_empty())
        .or_else(|| desktop.clone()).unwrap_or_else(|| "Notification".into());
    // ponytail: the sender-pid hint only; ask the bus for the sender's pid if apps without it show unnamed
    let launcher = hint::<i64>(&hints, "sender-pid").or_else(|| hint::<i32>(&hints, "sender-pid").map(i64::from)).and_then(|p| u32::try_from(p).ok()).or_else(|| hint::<u32>(&hints, "sender-pid"))
        .and_then(|pid| std::fs::read(format!("/proc/{pid}/cmdline")).ok()).map(|c| apps::launcher_names(&c)).unwrap_or_default();
    let who = apps::identify(&apps::entries(), &app, &app_icon, desktop.as_deref(), &body, &launcher);
    // The summary is plain text in the spec; only the body carries markup.
    let mut n = Note::new(id, &who.app, summary.trim(), &plain(&who.body));
    n.context = who.context;
    n.urgency = hint::<u8>(&hints, "urgency").unwrap_or(1).min(2);
    n.value = hint::<i32>(&hints, "value").map(|v| (v as f32 / 100.0).clamp(0.0, 1.0));
    n.tag = hint::<String>(&hints, "x-dunst-stack-tag")
        .or_else(|| hint::<String>(&hints, "x-canonical-private-synchronous")).filter(|t| !t.is_empty());
    n.resident = hint::<bool>(&hints, "resident").unwrap_or(false);
    n.transient = hint::<bool>(&hints, "transient").unwrap_or(false);
    n.icon = who.icon.map(Picture::File);
    let image_path = hint::<String>(&hints, "image-path").or_else(|| hint::<String>(&hints, "image_path"));
    // A theme icon's name there (`notify-send -i drive-harddisk`) is an icon, not a picture.
    if let Some(name) = image_path.as_deref().filter(|p| !p.starts_with('/') && !p.contains("://")) {
        if let Some(icon) = crate::sources::icon_path(name, None) { n.icon = Some(Picture::File(icon)); }
    }
    n.image = ["image-data", "image_data", "icon_data"].iter()
        .find_map(|k| hints.get(*k).and_then(image_data_hint))
        .or_else(|| image_path.as_deref().and_then(picture_file).map(Picture::File));
    (n.has_default, n.actions) = split_actions(&actions);
    n.timeout = match expire_timeout {
        0 => Timeout::Never,
        t if t > 0 => Timeout::After(Duration::from_millis(t as u64)),
        _ => Timeout::Default,
    };
    n
}

/// The spec's `image-data` hint, `(iiibiiay)`.
fn image_data_hint(v: &OwnedValue) -> Option<Picture> {
    let s = zbus::Structure::try_from(v.try_clone().ok()?).ok()?;
    let f = s.fields();
    let int = |i: usize| -> Option<i32> { i32::try_from(f.get(i)?).ok() };
    let alpha = bool::try_from(f.get(3)?).ok()?;
    let data = <Vec<u8>>::try_from(f.get(6)?.try_clone().ok()?).ok()?;
    image_data(int(0)?, int(1)?, int(2)?, alpha, int(4)?, int(5)?, &data)
}

/// Decodes a note's pictures through the bar's image cache (which wakes the bars and cards
/// when they're ready).
pub(crate) fn decode(n: &mut Note) {
    let images = crate::hub::images();
    let load = |p: &Picture, pt: f32| match p {
        Picture::File(path) => images.file(path, pt, 2.0),
        Picture::Rgba { width, height, bytes } => images.rgba(*width, *height, bytes.clone()),
    };
    n.icon_img = n.icon.as_ref().map(|p| load(p, 20.0));
    n.image_img = n.image.as_ref().map(|p| load(p, 44.0));
}

pub const NAME: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";

struct Server { next: AtomicU32, jobs: std::sync::mpsc::Sender<Job> }

/// Bus calls, applied one at a time in the order they arrived: a slow build (icon lookups,
/// picture decoding) can't let an older volume or progress update land after a newer one.
enum Job { Notify(Request, tokio::sync::oneshot::Sender<()>), Close(u32) }

fn worker(jobs: std::sync::mpsc::Receiver<Job>) {
    for job in jobs {
        match job {
            Job::Notify(request, done) => {
                let id = request.id;
                // Caught: a hint that trips a bug loses its card, but the sender still gets its answer.
                match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| { let mut n = build(request); decode(&mut n); n })) {
                    Ok(n) => super::with(move |s, now| s.upsert(n, now)),
                    Err(_) => eprintln!("andrew-bar: notification {id} tripped a bug and isn't shown"),
                }
                let _ = done.send(());
            }
            Job::Close(id) => super::with(|s, _| s.withdraw(id)),
        }
    }
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl Server {
    fn get_capabilities(&self) -> Vec<&'static str> {
        vec!["actions", "body", "body-markup", "persistence", "x-canonical-private-synchronous"]
    }

    #[allow(clippy::too_many_arguments)]
    async fn notify(&self, app_name: String, replaces_id: u32, app_icon: String, summary: String, body: String,
        actions: Vec<String>, hints: HashMap<String, OwnedValue>, expire_timeout: i32) -> u32 {
        let id = assign(&self.next, replaces_id);
        // One line per notification, for working out why an app shows the way it does.
        let desktop: Option<String> = hint(&hints, "desktop-entry");
        let mut keys: Vec<&str> = hints.keys().map(String::as_str).collect();
        keys.sort();
        eprintln!("andrew-bar: notify {id}: app {app_name:?} icon {app_icon:?} desktop-entry {desktop:?} hints {keys:?}");
        let request = Request { id, app_name, app_icon, summary, body, actions, hints, expire_timeout };
        let (done, applied) = tokio::sync::oneshot::channel();
        if self.jobs.send(Job::Notify(request, done)).is_ok() { let _ = applied.await; }
        id
    }

    fn close_notification(&self, id: u32) { let _ = self.jobs.send(Job::Close(id)); }

    fn get_server_information(&self) -> (&'static str, &'static str, &'static str, &'static str) {
        ("andrew-bar", "andrew-shell", "0.1", "1.2")
    }
}

/// Serves the bus name, then emits what the store owes as it arrives. The name is never taken
/// from another daemon: if one holds it, the bar waits in the bus's queue and serves once that
/// daemon exits (a bar restarting over its old self, or SwayNC being stopped).
pub async fn serve(mut owed: tokio::sync::mpsc::UnboundedReceiver<super::store::Out>) -> zbus::Result<()> {
    use futures_util::StreamExt;
    use super::store::Out;
    use zbus::fdo::{RequestNameFlags, RequestNameReply};
    let (jobs, queue) = std::sync::mpsc::channel();
    let _ = std::thread::Builder::new().name("notify-build".into()).spawn(move || worker(queue));
    let conn = zbus::connection::Builder::session().serve_at(PATH, Server { next: AtomicU32::new(1), jobs }).build().await?;
    let dbus = zbus::fdo::DBusProxy::new(&conn).await?;
    // Subscribed before asking, so the hand-over can't slip between the two.
    let mut acquired = dbus.receive_name_acquired().await?;
    if conn.request_name_with_flags(NAME, RequestNameFlags::empty()).await? != RequestNameReply::PrimaryOwner {
        let owner = dbus.get_name_owner(NAME.try_into()?).await.map(|o| o.to_string()).unwrap_or_default();
        eprintln!("andrew-bar: notifications: {owner} holds {NAME}; waiting for it");
        loop {
            let Some(signal) = acquired.next().await else { return Ok(()) };
            if signal.args().is_ok_and(|a| a.name() == NAME) { break; }
        }
        eprintln!("andrew-bar: notifications: serving {NAME}");
    }
    crate::hub::set(|d| d.notify.owned = true);
    while let Some(out) = owed.recv().await {
        let sent = match out {
            Out::Closed(id, reason) => conn.emit_signal(None::<zbus::names::BusName>, PATH, NAME, "NotificationClosed", &(id, reason as u32)).await,
            // ponytail: no ActivationToken; the vendored Rune can't ask for one, so clicked apps may not raise their windows
            Out::Action(id, key) => conn.emit_signal(None::<zbus::names::BusName>, PATH, NAME, "ActionInvoked", &(id, key)).await,
        };
        if let Err(e) = sent { eprintln!("andrew-bar: notifications: {e}"); }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::Variant as Value;

    fn req(hints: Vec<(&str, Value<'static>)>, expire_timeout: i32) -> Request {
        Request {
            id: 7, app_name: "notify-send".into(), app_icon: String::new(), summary: "<b>T</b>".into(), body: "B".into(),
            actions: ["default", "Open", "r", "Reply"].map(String::from).to_vec(),
            hints: hints.into_iter().map(|(k, v)| (k.to_owned(), v.try_to_owned().unwrap())).collect(),
            expire_timeout,
        }
    }

    #[test]
    fn build_reads_urgency_value_tag_resident_transient() {
        let n = build(req(vec![
            ("urgency", Value::from(2u8)), ("value", Value::from(62i32)), ("x-dunst-stack-tag", Value::from("volume")),
            ("resident", Value::from(true)), ("transient", Value::from(true)),
        ], -1));
        assert_eq!(build(req(vec![], -1)).body, "B");
        assert_eq!((n.id, n.summary.as_str(), n.urgency, n.value, n.tag.as_deref(), n.resident, n.transient), (7, "<b>T</b>", 2, Some(0.62), Some("volume"), true, true));
        assert!(n.has_default);
        assert_eq!(n.actions, vec![("r".to_owned(), "Reply".to_owned())]);
        let n = build(req(vec![("x-canonical-private-synchronous", Value::from("bright"))], -1));
        assert_eq!((n.urgency, n.tag.as_deref(), n.resident), (1, Some("bright"), false));
    }

    #[test]
    fn build_keeps_summary_as_plain_text() {
        let mut r = req(vec![], -1);
        r.summary = "Build <main> failed".into();
        assert_eq!(build(r).summary, "Build <main> failed");
    }

    #[test]
    fn build_timeout_from_expire_timeout() {
        assert_eq!(build(req(vec![], -1)).timeout, Timeout::Default);
        assert_eq!(build(req(vec![], 0)).timeout, Timeout::Never);
        assert_eq!(build(req(vec![], 3000)).timeout, Timeout::After(Duration::from_secs(3)));
    }

    #[test]
    fn build_image_path_name_is_an_icon_not_a_picture() {
        let n = build(req(vec![("image-path", Value::from("drive-harddisk"))], -1));
        assert_eq!(n.image, None);
        let file = std::env::temp_dir().join("andrew-bar-test-picture.png");
        std::fs::write(&file, b"x").unwrap();
        let n = build(req(vec![("image-path", Value::from(format!("file://{}", file.display())))], -1));
        assert_eq!(n.image, Some(Picture::File(file)));
        let n = build(req(vec![("image-path", Value::from("/nonexistent/x.png"))], -1));
        assert_eq!(n.image, None);
    }
}
