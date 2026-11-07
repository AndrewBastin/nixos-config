//! Network state read straight from NetworkManager over DBus: once at start, then again after
//! each burst of NetworkManager signals (signal strength, networks coming and going, the
//! radio switch, cables, VPNs, saved connections changing). No polling, no nmcli.

use std::collections::HashMap;
use std::time::Duration;

use zbus::{Connection, MatchRule, OwnedObjectPath, OwnedVariant};

use crate::hub;
use crate::sources::{Link, Vpn, WifiNet, Wired, merge_networks};

const NM: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const PROPS: &str = "org.freedesktop.DBus.Properties";
const DEVICE_ETHERNET: u32 = 1;
const DEVICE_WIFI: u32 = 2;

pub fn start() {
    crate::rt::spawn(async { if let Err(e) = watch().await { eprintln!("andrew-bar: NetworkManager: {e}"); } });
}

async fn watch() -> zbus::Result<()> {
    // Subscribe before the first read, so nothing between the two is missed.
    let rule = MatchRule::builder().msg_type(zbus::message::Type::Signal).sender(NM).build()?;
    let (conn, mut signals) = crate::rt::system_signals(rule).await?;
    // What's been read, so a signal costs only what it changed: saved connections are re-read
    // only when they change, access points are looked up once each (strength updates carry
    // their value), and the rest only when something other than a strength moved.
    let mut saved: Option<Saved> = None;
    let mut aps: HashMap<OwnedObjectPath, Ap> = HashMap::new();
    let mut state: Option<State> = None;
    loop {
        let read = async {
            if saved.is_none() { saved = Some(read_saved(&conn).await?); }
            if state.is_none() { state = Some(read_state(&conn, &mut aps).await?); }
            zbus::Result::Ok(())
        };
        match read.await {
            Ok(()) => if let (Some(saved), Some(state)) = (&saved, &state) { publish(snapshot(saved, state, &aps)) },
            Err(e) => eprintln!("andrew-bar: NetworkManager: {e}"),
        }
        let Some(first) = signals.recv().await else { return Ok(()) };
        // A scan updates every access point at once: take the whole burst as one change.
        let settle = tokio::time::Instant::now() + Duration::from_millis(250);
        let mut burst = vec![first];
        while let Ok(Some(m)) = tokio::time::timeout_at(settle, signals.recv()).await { burst.push(m); }
        for m in burst {
            let h = m.header();
            let path = h.path().map(|p| p.as_str().to_owned()).unwrap_or_default();
            if path.starts_with("/org/freedesktop/NetworkManager/Settings") {
                saved = None;
                continue;
            }
            if path.starts_with("/org/freedesktop/NetworkManager/AccessPoint/") && h.member().is_some_and(|m| m == "PropertiesChanged")
                && let Ok((_, mut changed, _)) = m.body().deserialize::<(String, HashMap<String, OwnedVariant>, Vec<String>)>()
                && let Ok(key) = OwnedObjectPath::try_from(path.as_str())
                && let Some(ap) = aps.get_mut(&key)
            {
                if let Some(strength) = take::<u8>(&mut changed, "Strength") { ap.strength = strength; }
                changed.remove("LastSeen");
                if changed.is_empty() { continue; }
                // Anything else about it changed (rare): look it up again.
                aps.remove(&key);
            }
            // A scan's finishing time changing (each scan) shows nothing.
            if h.member().is_some_and(|m| m == "PropertiesChanged")
                && let Ok((_, changed, gone)) = m.body().deserialize::<(String, HashMap<String, OwnedVariant>, Vec<String>)>()
                && gone.is_empty() && !changed.is_empty() && changed.keys().all(|k| k == "LastScan")
            { continue; }
            state = None;
        }
    }
}

/// Publishes a snapshot to the bars, if it changes what they show.
fn publish(snap: Snapshot) {
    let shown = hub::data().wifi.networks.clone();
    let networks = merge_networks(snap.aps, &shown);
    // Most signals change nothing visible once the dead band has had its say. The bar shows
    // the joined network; the rest are only in the open panel.
    let joined = |n: &[WifiNet]| n.iter().find(|n| n.active).cloned();
    let (bar, panel) = {
        let d = hub::data();
        (snap.wifi_enabled != d.wifi.enabled || joined(&networks) != joined(&shown) || snap.vpns != d.vpns || snap.wired != d.wired, networks != shown)
    };
    let apply = |d: &mut crate::Data| { d.wifi.enabled = snap.wifi_enabled; d.wifi.networks = networks; d.vpns = snap.vpns; d.wired = snap.wired; };
    if bar { hub::set(apply) } else if panel { hub::set_where(|b| b.wifi_open, apply) }
}

async fn call<R>(conn: &Connection, path: &str, iface: &str, method: &str, body: &(impl serde::Serialize + zbus::DynamicType)) -> zbus::Result<R>
where R: serde::de::DeserializeOwned + zbus::Type {
    conn.call_method(Some(NM), path, Some(iface), method, body).await?.body().deserialize()
}

async fn props(conn: &Connection, path: &str, iface: &str) -> zbus::Result<HashMap<String, OwnedVariant>> {
    call(conn, path, PROPS, "GetAll", &(iface,)).await
}

fn take<T: TryFrom<OwnedVariant>>(p: &mut HashMap<String, OwnedVariant>, key: &str) -> Option<T> {
    T::try_from(p.remove(key)?).ok()
}

struct Snapshot {
    wifi_enabled: bool,
    /// Every access point in range (unmerged), saved ones marked by connection UUID.
    aps: Vec<WifiNet>,
    /// Saved VPN and WireGuard connections, by name.
    vpns: Vec<Vpn>,
    /// Ethernet ports with a cable in.
    wired: Vec<Wired>,
}

/// Saved connections: Wi-Fi by SSID bytes (so a renamed connection still matches), and VPNs
/// (name, UUID, full tunnel).
struct Saved { known: HashMap<Vec<u8>, String>, vpns: Vec<(String, String, bool)> }

/// One access point, as last read or updated by its signals.
struct Ap { ssid: Vec<u8>, strength: u8, secure: bool }

/// NetworkManager's switches, connections and devices: everything but saved connections and
/// access points' own properties.
struct State {
    wifi_enabled: bool,
    /// Active connections' states by UUID.
    active: HashMap<String, Link>,
    wired: Vec<Wired>,
    /// The Wi-Fi devices' access points in range, and the one each is joined to.
    ap_paths: Vec<OwnedObjectPath>,
    active_aps: Vec<OwnedObjectPath>,
}

async fn read_saved(conn: &Connection) -> zbus::Result<Saved> {
    let mut known = HashMap::new();
    let mut vpns = Vec::new();
    let saved: Vec<OwnedObjectPath> = call(conn, "/org/freedesktop/NetworkManager/Settings", "org.freedesktop.NetworkManager.Settings", "ListConnections", &()).await?;
    for c in saved {
        // Connections other users own can refuse us; they aren't ours to use anyway.
        let Ok(mut s) = call::<HashMap<String, HashMap<String, OwnedVariant>>>(conn, c.as_str(), "org.freedesktop.NetworkManager.Settings.Connection", "GetSettings", &()).await else { continue };
        let Some(mut meta) = s.remove("connection") else { continue };
        let (Some(uuid), Some(kind)) = (take::<String>(&mut meta, "uuid"), take::<String>(&mut meta, "type")) else { continue };
        match kind.as_str() {
            "802-11-wireless" => if let Some(ssid) = s.get_mut("802-11-wireless").and_then(|w| take::<Vec<u8>>(w, "ssid")) { known.insert(ssid, uuid); },
            // ponytail: never-default only; a WireGuard peer without 0.0.0.0/0 counts as full
            // tunnel too. Read peers' allowed-ips if one ever shows up wrongly exclusive.
            "vpn" | "wireguard" => vpns.push((
                take::<String>(&mut meta, "id").unwrap_or_default(),
                uuid,
                !s.get_mut("ipv4").and_then(|p| take::<bool>(p, "never-default")).unwrap_or(false),
            )),
            _ => {}
        }
    }
    vpns.sort();
    Ok(Saved { known, vpns })
}

/// Reads the switches, active connections and devices, and any access point not yet in `aps`
/// (dropping those gone out of range).
async fn read_state(conn: &Connection, aps: &mut HashMap<OwnedObjectPath, Ap>) -> zbus::Result<State> {
    let mut nm = props(conn, NM_PATH, NM).await?;
    let wifi_enabled = take::<bool>(&mut nm, "WirelessEnabled").unwrap_or(false);

    // NM_ACTIVE_CONNECTION_STATE: 1 activating, 2 activated.
    let mut active: HashMap<String, Link> = HashMap::new();
    for a in take::<Vec<OwnedObjectPath>>(&mut nm, "ActiveConnections").unwrap_or_default() {
        let Ok(mut p) = props(conn, a.as_str(), "org.freedesktop.NetworkManager.Connection.Active").await else { continue };
        let link = match take::<u32>(&mut p, "State") { Some(1) => Link::Connecting, Some(2) => Link::On, _ => Link::Off };
        if let Some(uuid) = take::<String>(&mut p, "Uuid") { active.insert(uuid, link); }
    }

    let (mut wired, mut ap_paths, mut active_aps) = (Vec::new(), Vec::new(), Vec::new());
    let devices: Vec<OwnedObjectPath> = call(conn, NM_PATH, NM, "GetDevices", &()).await?;
    for dev in devices {
        let mut d = props(conn, dev.as_str(), "org.freedesktop.NetworkManager.Device").await?;
        match take::<u32>(&mut d, "DeviceType") {
            Some(DEVICE_ETHERNET) => {
                // NM_DEVICE_STATE: 10 unmanaged, 20 unavailable (no cable), 30 disconnected,
                // 40..=90 on the way up, 100 activated, 110+ going down or failed.
                let state = take::<u32>(&mut d, "State").unwrap_or(0);
                if state <= 20 { continue; }
                let link = match state { 100 => Link::On, 40..=90 => Link::Connecting, _ => Link::Off };
                wired.push(Wired { iface: take::<String>(&mut d, "Interface").unwrap_or_default(), link });
            }
            Some(DEVICE_WIFI) if wifi_enabled => {
                let mut w = props(conn, dev.as_str(), "org.freedesktop.NetworkManager.Device.Wireless").await?;
                active_aps.extend(take::<OwnedObjectPath>(&mut w, "ActiveAccessPoint"));
                ap_paths.extend(take::<Vec<OwnedObjectPath>>(&mut w, "AccessPoints").unwrap_or_default());
            }
            _ => {}
        }
    }
    wired.sort_by(|a, b| a.iface.cmp(&b.iface));
    aps.retain(|p, _| ap_paths.contains(p));
    for ap in &ap_paths {
        if aps.contains_key(ap) { continue; }
        // An access point can vanish between the list and this read.
        let Ok(mut a) = props(conn, ap.as_str(), "org.freedesktop.NetworkManager.AccessPoint").await else { continue };
        let flag = |a: &mut HashMap<String, OwnedVariant>, k| take::<u32>(a, k).unwrap_or(0);
        // Privacy (WEP) or any WPA/RSN security.
        let secure = flag(&mut a, "Flags") & 1 != 0 || flag(&mut a, "WpaFlags") != 0 || flag(&mut a, "RsnFlags") != 0;
        aps.insert(ap.clone(), Ap { ssid: take::<Vec<u8>>(&mut a, "Ssid").unwrap_or_default(), strength: take::<u8>(&mut a, "Strength").unwrap_or(0), secure });
    }
    Ok(State { wifi_enabled, active, wired, ap_paths, active_aps })
}

/// What the bars show, from what's been read: no calls.
fn snapshot(saved: &Saved, state: &State, aps: &HashMap<OwnedObjectPath, Ap>) -> Snapshot {
    let vpns = saved.vpns.iter().map(|(name, uuid, full_tunnel)| Vpn {
        name: name.clone(), uuid: uuid.clone(), full_tunnel: *full_tunnel, link: state.active.get(uuid).copied().unwrap_or_default(),
    }).collect();
    let aps = state.ap_paths.iter().filter_map(|p| Some((p, aps.get(p)?))).filter(|(_, a)| !a.ssid.is_empty()).map(|(p, a)| WifiNet {
        ssid: String::from_utf8_lossy(&a.ssid).into_owned(),
        signal: a.strength,
        secure: a.secure,
        active: state.active_aps.contains(p),
        known: saved.known.get(&a.ssid).cloned(),
    }).collect();
    Snapshot { wifi_enabled: state.wifi_enabled, aps, vpns, wired: state.wired.clone() }
}
