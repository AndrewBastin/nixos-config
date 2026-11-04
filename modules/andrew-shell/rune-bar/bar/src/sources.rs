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
    let default = objs.iter()
        .filter(|o| o["type"] == "PipeWire:Interface:Metadata" && o["props"]["metadata.name"] == "default")
        .flat_map(|o| o["metadata"].as_array().into_iter().flatten())
        .find(|m| m["key"] == "default.audio.sink")
        .and_then(|m| m["value"]["name"].as_str());
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
        let kind = if p["device.api"] == "bluez5" { SinkKind::Bluetooth } else if node.contains("HDMI") { SinkKind::Display } else { SinkKind::Speaker };
        let mac = p["api.bluez5.address"].as_str().map(str::to_owned);
        Some(Sink { id: o["id"].as_u64()?, name, kind, default: Some(node) == default, mac })
    }).collect();
    out.sort_by(|a, b| a.name.cmp(&b.name));
    out
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

/// Spawns `cmd` and hands each stdout line to `f`, restarting it if it exits.
fn lines(cmd: &'static str, args: &'static [&'static str], f: impl Fn(&str) + Send + 'static) {
    std::thread::spawn(move || loop {
        let mut command = Command::new(cmd);
        command.args(args).stdout(Stdio::piped()).stderr(Stdio::null());
        // Helpers like `upower --monitor` rarely write, so a dead pipe alone won't stop them:
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
            Err(e) => eprintln!("andrew-bar: {cmd}: {e}"),
        }
        std::thread::sleep(Duration::from_secs(2));
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

/// Which `pw-dump --monitor` lines can change what the bar shows: outputs (nodes), cards
/// (devices) and the default-device metadata appearing, changing or going. Clients and ports
/// churn constantly (the bar's own `pw-dump` and `wpctl` runs are clients, so reacting to
/// them refreshed in a loop); removals carry only an id, so the ids of the kinds that matter
/// are remembered.
#[derive(Default)]
struct PwFilter { id: Option<u64>, watched: std::collections::HashSet<u64> }

impl PwFilter {
    fn relevant(&mut self, line: &str) -> bool {
        // Each object's own fields sit four spaces in.
        let Some(field) = line.strip_prefix("    \"") else { return false };
        if let Some(id) = field.strip_prefix("id\": ") {
            self.id = id.trim_end_matches(',').parse().ok();
        } else if let Some(kind) = field.strip_prefix("type\": \"PipeWire:Interface:") {
            if ["Node\"", "Device\"", "Metadata\""].iter().any(|k| kind.starts_with(k)) {
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
    // "Volume: 0.76 [MUTED]"
    let vol = output("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"]);
    let inspect = output("wpctl", &["inspect", "@DEFAULT_AUDIO_SINK@"]);
    let prop = |key: &str| inspect.lines().find_map(|l| {
        let l = l.trim_start_matches([' ', '*']);
        l.strip_prefix(key)?.strip_prefix(" = ")?.trim_matches('"').to_owned().into()
    });
    Audio {
        volume: vol.split_whitespace().nth(1).and_then(|v| v.parse::<f32>().ok()).map_or(0, |v| (v * 100.0).round() as u32),
        muted: vol.contains("[MUTED]"),
        bluetooth: inspect.contains("bluez"),
        name: prop("node.description").or_else(|| prop("node.name")).unwrap_or_else(|| "Audio Device".into()),
        sinks: sinks(&dump),
        bt_names: bt_names(&dump),
    }
}

fn battery() -> Option<Battery> {
    let info = output("upower", &["-i", "/org/freedesktop/UPower/devices/DisplayDevice"]);
    let field = |key: &str| info.lines().find_map(|l| l.trim().strip_prefix(key).map(|v| v.trim().to_owned()));
    let percent = field("percentage:")?.trim_end_matches('%').parse::<f32>().ok()?.ceil() as u32;
    let charging = field("state:").as_deref() == Some("charging");
    let time = field(if charging { "time to full:" } else { "time to empty:" });
    Some(Battery { percent, charging, time })
}

/// The freedesktop icon file for `name`: a path as given, else hicolor or pixmaps, as
/// Quickshell's `iconPath` finds it. SVG wins over the largest PNG.
pub fn icon_path(name: &str, theme_path: Option<&str>) -> Option<PathBuf> {
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
    lines("librepods-ctl", &["watch"], |line| if let Ok(a) = serde_json::from_str::<AirPods>(line) { hub::put(|d| &mut d.airpods, Some(a)) });
    lines("calendar-status", &["--horizon-hours", "168", "--since-hours", "24"], |line| {
        #[derive(Deserialize)]
        struct Out { #[serde(default)] events: Vec<Event> }
        if let Ok(o) = serde_json::from_str::<Out>(line) { hub::put(|d| &mut d.events, o.events) }
    });
    let mut pw = PwFilter::default();
    on_change("pw-dump", &["--monitor", "--no-colors"], move |l| pw.relevant(l), || hub::put(|d| &mut d.audio, audio()));
    crate::nm::start();
    on_change("upower", &["--monitor"], |_| true, || hub::put(|d| &mut d.battery, battery()));
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
    fn pw_filter() {
        let mut f = super::PwFilter::default();
        let obj = |id: u32, kind: &str| format!("  {{\n    \"id\": {id},\n    \"type\": \"PipeWire:Interface:{kind}\",\n    \"info\": {{\n      \"id\": 9,\n    }}\n  }}");
        let gone = |id: u32| format!("  {{\n    \"id\": {id},\n    \"info\": null\n  }}");
        let fires = |f: &mut super::PwFilter, text: String| text.lines().fold(false, |any, l| f.relevant(l) | any);
        // A client (the bar's own pw-dump) coming and going is ignored; a sink isn't.
        assert!(!fires(&mut f, obj(170, "Client")));
        assert!(!fires(&mut f, gone(170)));
        assert!(fires(&mut f, obj(35, "Node")));
        assert!(fires(&mut f, gone(35)));
        assert!(!fires(&mut f, gone(35)));
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
