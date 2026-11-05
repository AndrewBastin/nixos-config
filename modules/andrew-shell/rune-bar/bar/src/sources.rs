//! Background threads that feed `Data`. Each one mirrors a QML singleton from the Quickshell
//! bar: the same helper binaries, the same JSON lines.

use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::Duration;

use serde::Deserialize;

use crate::hub;

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
pub struct Toplevel {
    pub icon_name: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
pub struct Workspace {
    pub id: i64,
    pub name: String,
    pub active: bool,
    pub urgent: bool,
    #[serde(default)]
    pub toplevels: Vec<Toplevel>,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
pub struct Monitor {
    #[serde(default)]
    pub workspaces: Vec<Workspace>,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
pub struct ActiveWindow {
    pub title: String,
    pub icon_name: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
pub struct Hyprland {
    #[serde(default)]
    pub monitors: HashMap<String, Monitor>,
    pub active_window: Option<ActiveWindow>,
}

#[derive(Clone, Debug, Deserialize, PartialEq)]
pub struct Event {
    pub title: String,
    pub start: i64,
    #[serde(default)]
    pub end: i64,
    pub calendar: String,
    pub url: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Audio {
    pub volume: u32,
    pub muted: bool,
    pub bluetooth: bool,
    pub name: String,
    /// Output devices, for the Sound panel.
    pub sinks: Vec<Sink>,
    /// Connected Bluetooth devices' names by address, for AirPods playing from another device
    /// (so with no output here).
    pub bt_names: std::collections::HashMap<String, String>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SinkKind { Speaker, Display, Bluetooth }

#[derive(Clone, Debug, PartialEq)]
pub struct Sink {
    /// PipeWire node id, for `wpctl set-default`.
    pub id: u64,
    pub name: String,
    pub kind: SinkKind,
    pub default: bool,
    /// A Bluetooth output's device address, to match librepods' AirPods.
    pub mac: Option<String>,
}

/// AirPods state from the librepods daemon (`librepods-ctl watch`).
#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
pub struct AirPods {
    pub connected: bool,
    pub mac: String,
    /// Noise control: off | anc | transparency | adaptive.
    pub mode: String,
    pub conversational_awareness: bool,
    pub battery: Option<u32>,
    /// This machine has the audio (not a peer such as an iPhone).
    pub owns: bool,
    #[serde(default)]
    pub peers: Vec<AirPodsPeer>,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq)]
pub struct AirPodsPeer {
    pub mac: String,
    pub name: Option<String>,
    pub owns: bool,
}

/// The output devices in one `pw-dump`, by name, leaving out ports nothing is plugged into
/// (an HDMI output with no monitor): their card route says `available: no`.
fn sinks(objs: &[serde_json::Value]) -> Vec<Sink> {
    let default = default_sink(objs);
    // (device id, card profile device) of every unplugged output route.
    let mut unplugged = std::collections::HashSet::new();
    for o in objs.iter().filter(|o| o["type"] == "PipeWire:Interface:Device") {
        for r in o["info"]["params"]["EnumRoute"].as_array().into_iter().flatten() {
            if r["direction"] != "Output" || r["available"] != "no" { continue; }
            for dev in r["devices"].as_array().into_iter().flatten() { unplugged.insert((o["id"].as_u64(), dev.as_u64())); }
        }
    }
    let mut out: Vec<Sink> = objs.iter().filter_map(|o| {
        let p = &o["info"]["props"];
        if p["media.class"] != "Audio/Sink" || unplugged.contains(&(p["device.id"].as_u64(), p["card.profile.device"].as_u64())) { return None; }
        let node = p["node.name"].as_str().unwrap_or_default();
        // The nick is the friendly one ("Speaker", a monitor's model); Bluetooth has none.
        let name = p["node.nick"].as_str().or(p["node.description"].as_str()).unwrap_or(node).to_owned();
        let display = { let n = node.to_ascii_lowercase(); n.contains("hdmi") || n.contains("displayport") };
        let kind = if p["device.api"] == "bluez5" { SinkKind::Bluetooth } else if display { SinkKind::Display } else { SinkKind::Speaker };
        let mac = p["api.bluez5.address"].as_str().map(str::to_owned);
        Some(Sink { id: o["id"].as_u64()?, name, kind, default: Some(node) == default, mac })
    }).collect();
    out.sort_by(|a, b| a.name.cmp(&b.name));
    out
}

/// The default output's node name, from the "default" metadata.
fn default_sink(objs: &[serde_json::Value]) -> Option<&str> {
    objs.iter()
        .filter(|o| o["type"] == "PipeWire:Interface:Metadata" && o["props"]["metadata.name"] == "default")
        .flat_map(|o| o["metadata"].as_array().into_iter().flatten())
        .find(|m| m["key"] == "default.audio.sink")
        .and_then(|m| m["value"]["name"].as_str())
}

/// What the bar shows of one `pw-dump`: the default output's volume, mute and name, and the
/// lists for the Sound panel. One process per change, where `wpctl` took two more.
fn audio_of(objs: &[serde_json::Value]) -> Audio {
    let default = default_sink(objs);
    let node = objs.iter().find(|o| o["info"]["props"]["media.class"] == "Audio/Sink" && o["info"]["props"]["node.name"].as_str() == default);
    let p = node.map(|o| &o["info"]["props"]);
    let props = node.and_then(|o| o["info"]["params"]["Props"].as_array()?.iter().find(|x| x["channelVolumes"].is_array()));
    // Channel volumes are linear; wpctl and the slider show their cube root.
    let vols: Vec<f64> = props.and_then(|x| x["channelVolumes"].as_array()).into_iter().flatten().filter_map(|v| v.as_f64()).collect();
    let linear = if vols.is_empty() { 0.0 } else { vols.iter().sum::<f64>() / vols.len() as f64 };
    Audio {
        volume: (linear.cbrt() * 100.0).round() as u32,
        muted: props.is_some_and(|x| x["mute"] == true),
        bluetooth: p.is_some_and(|p| p["device.api"] == "bluez5"),
        name: p.and_then(|p| p["node.description"].as_str().or(p["node.name"].as_str())).unwrap_or("Audio Device").to_owned(),
        sinks: sinks(objs),
        bt_names: bt_names(objs),
    }
}

fn bt_names(objs: &[serde_json::Value]) -> std::collections::HashMap<String, String> {
    objs.iter().filter(|o| o["type"] == "PipeWire:Interface:Device").filter_map(|o| {
        let p = &o["info"]["props"];
        Some((p["api.bluez5.address"].as_str()?.to_owned(), p["device.description"].as_str()?.to_owned()))
    }).collect()
}

/// Sets the default output's volume (0..=1). A drag sends many; one worker applies only the latest.
pub fn set_volume(v: f32) {
    static TX: std::sync::OnceLock<std::sync::Mutex<mpsc::Sender<f32>>> = std::sync::OnceLock::new();
    let tx = TX.get_or_init(|| {
        let (tx, rx) = mpsc::channel::<f32>();
        std::thread::spawn(move || while let Ok(mut v) = rx.recv() {
            while let Ok(newer) = rx.try_recv() { v = newer; }
            let _ = Command::new("wpctl").args(["set-volume", "@DEFAULT_AUDIO_SINK@", &format!("{v:.3}")]).output();
        });
        std::sync::Mutex::new(tx)
    });
    let _ = tx.lock().unwrap().send(v);
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Battery {
    pub percent: u32,
    pub charging: bool,
    /// "3.0 hours", as upower words it.
    pub time: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct WifiNet {
    pub ssid: String,
    pub signal: u8,
    pub secure: bool,
    pub active: bool,
    /// The UUID of NetworkManager's saved connection for it.
    pub known: Option<String>,
}

#[derive(Clone, Debug, Default)]
pub struct Wifi {
    pub enabled: bool,
    /// In range, one per SSID (strongest access point), strongest first.
    pub networks: Vec<WifiNet>,
    /// The SSID being joined, while nmcli works on it.
    pub joining: Option<String>,
    /// The last action that failed, keyed by the row it came from (SSID, VPN UUID or
    /// interface), and nmcli's reason.
    pub error: Option<(String, String)>,
}

/// A VPN or wired link's state, from NetworkManager's active-connection / device state.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum Link { #[default] Off, Connecting, On }

/// A saved VPN (or WireGuard) connection. A full-tunnel one takes the default route, so at
/// most one of those is up at a time; split-tunnel ones run alongside.
#[derive(Clone, Debug, PartialEq)]
pub struct Vpn { pub name: String, pub uuid: String, pub link: Link, pub full_tunnel: bool }

/// An Ethernet port with a cable in (unplugged ports aren't listed).
#[derive(Clone, Debug, PartialEq)]
pub struct Wired { pub iface: String, pub link: Link }

/// Strength changes smaller than this (from what's shown) are noise: a still laptop's access
/// point wanders a few points, which would flip the icon across a bar threshold.
const SIGNAL_DEADBAND: i16 = 8;

/// One row per SSID (several access points can share one), joined first, then strongest.
/// The joined network shows the strength of the access point actually in use, others their
/// strongest. Signals within the dead band of `shown` keep the shown value.
pub fn merge_networks(all: Vec<WifiNet>, shown: &[WifiNet]) -> Vec<WifiNet> {
    let mut nets: Vec<WifiNet> = Vec::new();
    for net in all {
        match nets.iter_mut().find(|n| n.ssid == net.ssid) {
            Some(n) if net.active => { n.active = true; n.signal = net.signal; }
            Some(n) if !n.active => n.signal = n.signal.max(net.signal),
            Some(_) => {}
            None => nets.push(net),
        }
    }
    for n in &mut nets {
        if let Some(old) = shown.iter().find(|o| o.ssid == n.ssid)
            && (n.signal as i16 - old.signal as i16).abs() < SIGNAL_DEADBAND { n.signal = old.signal; }
    }
    nets.sort_by(|a, b| b.active.cmp(&a.active).then(b.signal.cmp(&a.signal)));
    nets
}

/// Ask for a fresh scan; its results arrive as NetworkManager signals (see `nm`).
pub fn rescan_wifi() {
    std::thread::spawn(|| { let _ = Command::new("nmcli").args(["device", "wifi", "rescan"]).output(); });
}

pub fn set_wifi(on: bool) {
    hub::set(|d| d.wifi.enabled = on);
    std::thread::spawn(move || {
        let _ = Command::new("nmcli").args(["radio", "wifi", if on { "on" } else { "off" }]).output();
    });
}

/// Joins `ssid`: its saved connection by UUID, else a new one. A secured new network's
/// password is asked for by NetworkManager's secret agent (nm-applet's dialog), not by us.
pub fn join_wifi(ssid: String, known: Option<String>) {
    hub::set(|d| { d.wifi.joining = Some(ssid.clone()); d.wifi.error = None; });
    std::thread::spawn(move || {
        let mut cmd = Command::new("nmcli");
        match &known {
            Some(uuid) => cmd.args(["connection", "up", "uuid", uuid]),
            None => cmd.args(["device", "wifi", "connect", &ssid]),
        };
        let error = match cmd.stdin(Stdio::null()).output() {
            Ok(o) if o.status.success() => None,
            Ok(o) => {
                let err = String::from_utf8_lossy(&o.stderr);
                let msg = err.lines().last().unwrap_or("Couldn't join").trim_start_matches("Error: ").to_owned();
                // The password dialog was cancelled: not an error worth showing.
                (!msg.contains("Secrets were required")).then_some(msg)
            }
            Err(e) => Some(e.to_string()),
        };
        hub::set(|d| { d.wifi.joining = None; d.wifi.error = error.map(|e| (ssid, e)); });
    });
}

/// Runs each `nmcli` command in `steps` in turn for the panel row `key`, stopping at the first
/// failure, which shows under that row. The panel's state itself updates from
/// NetworkManager's signals (see `nm`).
pub fn nmcli_action(key: String, steps: Vec<Vec<String>>) {
    hub::set(|d| d.wifi.error = None);
    std::thread::spawn(move || {
        for args in steps {
            let error = match Command::new("nmcli").args(&args).stdin(Stdio::null()).output() {
                Ok(o) if o.status.success() => continue,
                Ok(o) => String::from_utf8_lossy(&o.stderr).lines().last().unwrap_or("Failed").trim_start_matches("Error: ").to_owned(),
                Err(e) => e.to_string(),
            };
            hub::set(|d| d.wifi.error = Some((key, error)));
            return;
        }
    });
}

/// Spawns `cmd` and hands each stdout line to `f`, restarting it if it exits: at once after a
/// long run, backing off to a minute if it keeps dying, and never if it isn't installed.
fn lines(cmd: &'static str, args: &'static [&'static str], f: impl Fn(&str) + Send + 'static) {
    let mut backoff = Duration::from_secs(2);
    std::thread::spawn(move || loop {
        let started = std::time::Instant::now();
        let mut command = Command::new(cmd);
        command.args(args).stdout(Stdio::piped()).stderr(Stdio::null());
        // Watchers like `librepods-ctl watch` rarely write, so a dead pipe alone won't stop them:
        // they get SIGTERM when this (spawning) thread goes, i.e. when the bar exits.
        // SAFETY: prctl is async-signal-safe.
        unsafe { std::os::unix::process::CommandExt::pre_exec(&mut command, || { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM); Ok(()) }); }
        match command.spawn() {
            Ok(mut child) => {
                for line in BufReader::new(child.stdout.take().unwrap()).lines().map_while(Result::ok) {
                    f(&line);
                }
                let _ = child.wait();
            }
            Err(e) => {
                eprintln!("andrew-bar: {cmd}: {e}");
                if e.kind() == std::io::ErrorKind::NotFound { return; }
            }
        }
        backoff = if started.elapsed() > Duration::from_secs(60) { Duration::from_secs(2) } else { (backoff * 2).min(Duration::from_secs(60)) };
        std::thread::sleep(backoff);
    });
}

/// Runs `query` now and again after every burst of output lines from the `watch` command
/// that `relevant` passes.
fn on_change(watch: &'static str, args: &'static [&'static str], relevant: impl FnMut(&str) -> bool + Send + 'static, query: impl Fn() + Send + 'static) {
    let (tx, rx) = mpsc::channel();
    let relevant = std::sync::Mutex::new(relevant);
    lines(watch, args, move |line| if relevant.lock().unwrap()(line) { let _ = tx.send(()); });
    std::thread::spawn(move || loop {
        query();
        if rx.recv().is_err() { return; }
        // One volume key press is dozens of pw-dump lines; settle them into one query.
        while rx.recv_timeout(Duration::from_millis(40)).is_ok() {}
    });
}

/// Which `pw-dump --monitor` lines can change what the bar shows: outputs (sink nodes), cards
/// (devices) and the default-device metadata appearing, changing or going. Clients, ports and
/// apps' playback streams churn constantly (the bar's own `pw-dump` and `wpctl` runs are
/// clients, so reacting to them refreshed in a loop); removals carry only an id, so the ids of
/// the kinds that matter are remembered.
#[derive(Default)]
struct PwFilter { id: Option<u64>, node: bool, watched: std::collections::HashSet<u64> }

impl PwFilter {
    fn relevant(&mut self, line: &str) -> bool {
        // A node is an output only by its class, a few lines further into the object.
        if self.node && line == "        \"media.class\": \"Audio/Sink\"," {
            self.node = false;
            if let Some(id) = self.id { self.watched.insert(id); }
            return true;
        }
        // Each object's own fields sit four spaces in.
        let Some(field) = line.strip_prefix("    \"") else { return false };
        if let Some(id) = field.strip_prefix("id\": ") {
            self.id = id.trim_end_matches(',').parse().ok();
            self.node = false;
        } else if let Some(kind) = field.strip_prefix("type\": \"PipeWire:Interface:") {
            self.node = kind.starts_with("Node\"");
            if ["Device\"", "Metadata\""].iter().any(|k| kind.starts_with(k)) {
                if let Some(id) = self.id { self.watched.insert(id); }
                return true;
            }
        } else if field == "info\": null" {
            return self.id.is_some_and(|id| self.watched.remove(&id));
        }
        false
    }
}

fn output(cmd: &str, args: &[&str]) -> String {
    Command::new(cmd).args(args).output().map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default()
}

fn audio() -> Audio {
    let dump = match serde_json::from_str(&output("pw-dump", &["--no-colors"])) { Ok(serde_json::Value::Array(objs)) => objs, _ => Vec::new() };
    audio_of(&dump)
}

/// The bar's battery from UPower's DisplayDevice properties (None without a battery). State 1
/// is charging; the time is worded as `upower -i` words it.
fn battery_of(present: bool, percentage: f64, state: u32, to_empty: i64, to_full: i64) -> Option<Battery> {
    if !present { return None; }
    let charging = state == 1;
    let secs = if charging { to_full } else { to_empty } as f64;
    let time = match secs {
        s if s <= 0.0 => None,
        s if s < 60.0 => Some(format!("{s:.0} seconds")),
        s if s < 3600.0 => Some(format!("{:.1} minutes", s / 60.0)),
        s if s < 86_400.0 => Some(format!("{:.1} hours", s / 3600.0)),
        s => Some(format!("{:.1} days", s / 86_400.0)),
    };
    Some(Battery { percent: percentage.ceil() as u32, charging, time })
}

const DISPLAY_DEVICE: &str = "/org/freedesktop/UPower/devices/DisplayDevice";

/// Reads UPower's DisplayDevice now and again on each of its PropertiesChanged signals: no
/// processes, and other devices (a mouse's battery) don't wake the bar.
// ponytail: UPower restarting mid-session ends the watch until the bar restarts.
async fn watch_battery() -> zbus::Result<()> {
    let conn = crate::rt::system().await?;
    use futures_util::StreamExt;
    let rule = zbus::MatchRule::builder().msg_type(zbus::message::Type::Signal).sender("org.freedesktop.UPower")
        .path(DISPLAY_DEVICE).interface("org.freedesktop.DBus.Properties").member("PropertiesChanged").build()?;
    let mut signals = zbus::MessageStream::for_match_rule(rule, &conn, None).await?;
    loop {
        let reply = conn.call_method(Some("org.freedesktop.UPower"), DISPLAY_DEVICE, Some("org.freedesktop.DBus.Properties"), "GetAll", &("org.freedesktop.UPower.Device",)).await?;
        let mut p: HashMap<String, zbus::OwnedVariant> = reply.body().deserialize()?;
        let mut get = |k: &str| p.remove(k);
        let b = battery_of(
            get("IsPresent").and_then(|v| bool::try_from(v).ok()).unwrap_or(false),
            get("Percentage").and_then(|v| f64::try_from(v).ok()).unwrap_or(0.0),
            get("State").and_then(|v| u32::try_from(v).ok()).unwrap_or(0),
            get("TimeToEmpty").and_then(|v| i64::try_from(v).ok()).unwrap_or(0),
            get("TimeToFull").and_then(|v| i64::try_from(v).ok()).unwrap_or(0),
        );
        hub::put(|d| &mut d.battery, b);
        if signals.next().await.is_none() { return Ok(()); }
    }
}

/// The freedesktop icon file for `name`: a path as given, else hicolor or pixmaps, as
/// Quickshell's `iconPath` finds it. SVG wins over the largest PNG.
pub fn icon_path(name: &str, theme_path: Option<&str>) -> Option<PathBuf> {
    // Each lookup walks the icon directories (thousands of entries): remember the answers.
    // ponytail: an icon installed while the bar runs isn't found until it restarts.
    type Cache = HashMap<(String, Option<String>), Option<PathBuf>>;
    static CACHE: std::sync::Mutex<Option<Cache>> = std::sync::Mutex::new(None);
    let key = (name.to_owned(), theme_path.map(str::to_owned));
    if let Some(hit) = CACHE.lock().unwrap().get_or_insert_default().get(&key) { return hit.clone(); }
    let found = find_icon(name, theme_path);
    CACHE.lock().unwrap().get_or_insert_default().insert(key, found.clone());
    found
}

fn find_icon(name: &str, theme_path: Option<&str>) -> Option<PathBuf> {
    if name.starts_with('/') { return Some(PathBuf::from(name)).filter(|p| p.exists()); }
    let mut roots: Vec<PathBuf> = theme_path.into_iter().filter(|p| !p.is_empty()).map(PathBuf::from).collect();
    if let Some(home) = std::env::var_os("HOME") { roots.push(PathBuf::from(home).join(".local/share/icons")); }
    let data = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/share".into());
    for dir in data.split(':').filter(|d| !d.is_empty()) {
        roots.push(PathBuf::from(dir).join("icons/hicolor"));
        roots.push(PathBuf::from(dir).join("pixmaps"));
    }
    let mut best: Option<(u32, PathBuf)> = None;
    for root in roots { walk(&root, name, &mut best, 0); }
    best.map(|(_, p)| p)
}

fn walk(dir: &std::path::Path, name: &str, best: &mut Option<(u32, PathBuf)>, depth: u32) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if depth < 4 { walk(&path, name, best, depth + 1); }
            continue;
        }
        let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else { continue };
        if stem != name { continue; }
        // "scalable" ranks above any pixel size; "48x48" ranks 48.
        let rank = match path.extension().and_then(|e| e.to_str()) {
            Some("svg") => 10_000,
            Some("png") => dir.to_string_lossy().rsplit('/').find_map(|seg| seg.split('x').next()?.parse().ok()).unwrap_or(1),
            _ => continue,
        };
        if best.as_ref().is_none_or(|(r, _)| rank > *r) { *best = Some((rank, path)); }
    }
}

pub fn start() {
    lines("hyprland-info", &["--monitor"], |line| match serde_json::from_str::<Hyprland>(line) {
        Ok(h) => {
            let icons = h.monitors.values().flat_map(|m| &m.workspaces).flat_map(|w| &w.toplevels).filter_map(|t| t.icon_name.as_deref())
                .chain(h.active_window.as_ref().and_then(|w| w.icon_name.as_deref()));
            hub::app_icons(icons);
            hub::put(|d| &mut d.hypr, h);
        crate::check_monitors();
        }
        Err(e) => eprintln!("andrew-bar: hyprland-info: {e}"),
    });
    if crate::vm_mode() { return; }
    lines("librepods-ctl", &["watch"], |line| if let Ok(a) = serde_json::from_str::<AirPods>(line)
        && hub::data().airpods.as_ref() != Some(&a) {
        // Shown only in the Sound panel.
        hub::set_where(|b| b.sound_open, |d| d.airpods = Some(a));
    });
    lines("calendar-status", &["--horizon-hours", "168", "--since-hours", "24"], |line| {
        #[derive(Deserialize)]
        struct Out { #[serde(default)] events: Vec<Event> }
        if let Ok(o) = serde_json::from_str::<Out>(line) { hub::put(|d| &mut d.events, o.events) }
    });
    let mut pw = PwFilter::default();
    on_change("pw-dump", &["--monitor", "--no-colors"], move |l| pw.relevant(l), || {
        let a = audio();
        // The bar shows the default output; the lists are only in the open Sound panel.
        let seen = |a: &Audio| (a.volume, a.muted, a.bluetooth, a.name.clone());
        let (bar, panel) = { let d = hub::data(); (seen(&d.audio) != seen(&a), d.audio != a) };
        if bar { hub::set(|d| d.audio = a) } else if panel { hub::set_where(|b| b.sound_open, |d| d.audio = a) }
    });
    crate::nm::start();
    crate::rt::spawn(async { if let Err(e) = watch_battery().await { eprintln!("andrew-bar: UPower: {e}"); } });
    // The clock: wake on each minute boundary.
    std::thread::spawn(|| loop {
        hub::set(|d| d.now = crate::clock::now());
        let secs = crate::clock::now() % 60;
        std::thread::sleep(Duration::from_secs((60 - secs) as u64) + Duration::from_millis(50));
    });
}

#[cfg(test)]
mod tests {
    #[test]
    fn sink_list() {
        let dump = r#"[
          {"id":50,"type":"PipeWire:Interface:Device","info":{"params":{"EnumRoute":[
            {"direction":"Output","available":"no","devices":[0]},{"direction":"Output","available":"yes","devices":[1]}]}}},
          {"id":9,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},
           "metadata":[{"key":"default.audio.sink","value":{"name":"bluez_output.1"}}]},
          {"id":109,"info":{"props":{"media.class":"Audio/Sink","node.name":"alsa.HDMI3","node.nick":"HDMI 3","device.id":50,"card.profile.device":0}}},
          {"id":113,"info":{"props":{"media.class":"Audio/Sink","node.name":"alsa.HDMI2","node.nick":"DELL U2724DE","device.id":50,"card.profile.device":1}}},
          {"id":35,"info":{"props":{"media.class":"Audio/Sink","node.name":"bluez_output.1","node.description":"AirPods","device.api":"bluez5","device.id":61,"card.profile.device":1}}},
          {"id":75,"info":{"props":{"media.class":"Audio/Source","node.name":"mic"}}}
        ]"#;
        let objs: Vec<serde_json::Value> = serde_json::from_str(dump).unwrap();
        let rows: Vec<_> = super::sinks(&objs).into_iter().map(|s| (s.id, s.name, s.kind, s.default)).collect();
        // The unplugged HDMI 3 is left out; the same profile device on another card isn't.
        assert_eq!(rows, [(35, "AirPods".into(), super::SinkKind::Bluetooth, true), (113, "DELL U2724DE".into(), super::SinkKind::Display, false)]);
    }

    #[test]
    fn default_output() {
        let dump = r#"[
          {"id":9,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},
           "metadata":[{"key":"default.audio.sink","value":{"name":"bluez_output.1"}}]},
          {"id":113,"info":{"props":{"media.class":"Audio/Sink","node.name":"alsa.HDMI2"},"params":{"Props":[{"channelVolumes":[1.0,1.0],"mute":false}]}}},
          {"id":35,"info":{"props":{"media.class":"Audio/Sink","node.name":"bluez_output.1","node.description":"AirPods","device.api":"bluez5"},
           "params":{"Props":[{"volume":1.0},{"channelVolumes":[0.71902,0.71902],"mute":true}]}}}
        ]"#;
        let objs: Vec<serde_json::Value> = serde_json::from_str(dump).unwrap();
        let a = super::audio_of(&objs);
        // Channel volumes are cubic: 0.719 is wpctl's 0.90.
        assert_eq!((a.volume, a.muted, a.bluetooth, a.name.as_str()), (90, true, true, "AirPods"));
        assert_eq!(super::audio_of(&[]).name, "Audio Device");
    }

    #[test]
    fn battery_props() {
        use super::{Battery, battery_of};
        // UPower's State 1 is charging; times read as `upower -i` words them.
        assert_eq!(battery_of(true, 44.2, 1, 0, 3697), Some(Battery { percent: 45, charging: true, time: Some("1.0 hours".into()) }));
        assert_eq!(battery_of(true, 80.0, 2, 1500, 0), Some(Battery { percent: 80, charging: false, time: Some("25.0 minutes".into()) }));
        assert_eq!(battery_of(true, 100.0, 4, 0, 0).unwrap().time, None);
        assert_eq!(battery_of(false, 0.0, 0, 0, 0), None);
    }

    #[test]
    fn pw_filter() {
        let mut f = super::PwFilter::default();
        let obj = |id: u32, kind: &str| format!("  {{\n    \"id\": {id},\n    \"type\": \"PipeWire:Interface:{kind}\",\n    \"info\": {{\n      \"id\": 9,\n    }}\n  }}");
        let node = |id: u32, class: &str| format!("  {{\n    \"id\": {id},\n    \"type\": \"PipeWire:Interface:Node\",\n    \"info\": {{\n      \"props\": {{\n        \"media.class\": \"{class}\",\n      }}\n    }}\n  }}");
        let gone = |id: u32| format!("  {{\n    \"id\": {id},\n    \"info\": null\n  }}");
        let fires = |f: &mut super::PwFilter, text: String| text.lines().fold(false, |any, l| f.relevant(l) | any);
        // A client (the bar's own pw-dump) coming and going is ignored; a sink isn't.
        assert!(!fires(&mut f, obj(170, "Client")));
        assert!(!fires(&mut f, gone(170)));
        assert!(fires(&mut f, node(35, "Audio/Sink")));
        assert!(fires(&mut f, gone(35)));
        assert!(!fires(&mut f, gone(35)));
        // An app's playback stream starting, changing or going doesn't touch the outputs.
        assert!(!fires(&mut f, node(80, "Stream/Output/Audio")));
        assert!(!fires(&mut f, gone(80)));
        assert!(fires(&mut f, obj(47, "Device")));
    }

    #[test]
    fn wifi_merge() {
        let net = |ssid: &str, signal, active| super::WifiNet { ssid: ssid.into(), signal, active, ..Default::default() };
        // The joined network takes its in-use access point's strength, even if another is stronger.
        let nets = super::merge_networks(vec![net("Cafe", 60, false), net("Office", 90, false), net("Office", 55, true), net("Home", 37, false)], &[]);
        let rows: Vec<_> = nets.iter().map(|n| (n.ssid.as_str(), n.signal, n.active)).collect();
        assert_eq!(rows, [("Office", 55, true), ("Cafe", 60, false), ("Home", 37, false)]);
        // Jitter inside the dead band keeps what's shown; a real change goes through.
        let nets = super::merge_networks(vec![net("Office", 84, true), net("Cafe", 40, false)], &[net("Office", 79, true), net("Cafe", 60, false)]);
        let rows: Vec<_> = nets.iter().map(|n| (n.ssid.as_str(), n.signal)).collect();
        assert_eq!(rows, [("Office", 79), ("Cafe", 40)]);
    }
}
