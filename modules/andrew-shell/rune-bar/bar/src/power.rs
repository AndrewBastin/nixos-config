//! The battery item's panel: where the power goes (AlDente's power flow), UPower's recorded
//! power history, CPU/memory, and the apps estimated to draw the most. It's read only while the
//! panel is open, except a cheap snapshot of process CPU times every 5 minutes.

use std::collections::HashMap;

use crate::Bar;

/// Power flow in watts. `battery_w` is + while charging, − while discharging.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Flow { pub battery_w: f32, pub adapter_w: Option<f32>, pub on_ac: bool, pub system_w: Option<f32> }

/// `status`/`power_now` (µW) of the battery and (online, µV, µA) of each adapter.
fn flow(status: &str, power_uw: u64, adapters: &[(bool, u64, u64)]) -> Flow {
    let w = power_uw as f32 / 1e6;
    let battery_w = if status == "Discharging" { -w } else if status == "Charging" { w } else { 0.0 };
    let on_ac = adapters.iter().any(|a| a.0);
    let input: f32 = adapters.iter().filter(|a| a.0).map(|&(_, uv, ua)| uv as f32 * ua as f32 / 1e12).sum();
    // Less than the battery takes in is a stale reading (UCSI often reports 5 V × 3 A): unknown.
    let adapter_w = (input > 0.0 && input >= battery_w).then_some(input);
    let system_w = match adapter_w {
        _ if !on_ac => Some(-battery_w),
        Some(a) => Some((a - battery_w.max(0.0)).max(0.0)),
        None => None,
    };
    Flow { battery_w, adapter_w, on_ac, system_w }
}

const SUPPLIES: &str = "/sys/class/power_supply";

/// The system battery and the adapters among (name, type, scope) power supplies: a battery or
/// USB supply scoped to a device (a mouse) isn't the machine's.
fn pick_supplies(all: Vec<(String, String, String)>) -> (Option<String>, Vec<String>) {
    let mut battery = None;
    let mut adapters = Vec::new();
    for (name, kind, _) in all.into_iter().filter(|s| s.2 != "Device") {
        match kind.as_str() {
            "Battery" if battery.is_none() => battery = Some(name),
            "Mains" | "USB" => adapters.push(name),
            _ => {}
        }
    }
    adapters.sort();
    (battery, adapters)
}

fn sysfs(path: &std::path::Path) -> String { std::fs::read_to_string(path).unwrap_or_default().trim().to_owned() }
fn sysfs_num(path: &std::path::Path) -> u64 { sysfs(path).parse().unwrap_or(0) }

/// The machine's battery and adapters in sysfs.
fn supplies() -> (Option<String>, Vec<String>) {
    let all = std::fs::read_dir(SUPPLIES).into_iter().flatten().flatten().map(|e| {
        let dir = e.path();
        (e.file_name().to_string_lossy().into_owned(), sysfs(&dir.join("type")), sysfs(&dir.join("scope")))
    }).collect();
    pick_supplies(all)
}

/// The flow now. Adapters' voltage and current are read only while they're plugged in.
fn read_flow(battery: &str, adapters: &[String]) -> Flow {
    let at = |name: &str, f: &str| std::path::Path::new(SUPPLIES).join(name).join(f);
    let adapters: Vec<(bool, u64, u64)> = adapters.iter().map(|a| match sysfs_num(&at(a, "online")) == 1 {
        true => (true, sysfs_num(&at(a, "voltage_now")), sysfs_num(&at(a, "current_now"))),
        false => (false, 0, 0),
    }).collect();
    flow(&sysfs(&at(battery, "status")), sysfs_num(&at(battery, "power_now")), &adapters)
}

/// UPower's `GetHistory` points (time, W, state) as (time, W) while discharging, oldest first.
/// State 2 is discharging: what the system draws; charging points are the charge rate.
fn discharging(points: Vec<(u32, f64, u32)>) -> Vec<(u32, f32)> {
    let mut out: Vec<(u32, f32)> = points.into_iter().filter(|p| p.2 == 2).map(|p| (p.0, p.1 as f32)).collect();
    out.sort_by_key(|p| p.0);
    out
}

/// The battery power UPower recorded over the last `secs`, on battery, in at most `points`.
async fn history(bus: &zbus::Connection, battery: &str, secs: u32, points: u32) -> Vec<(u32, f32)> {
    // UPower names a sysfs battery's object after it.
    let path = format!("/org/freedesktop/UPower/devices/battery_{}", battery.replace(|c: char| !c.is_ascii_alphanumeric(), "_"));
    let reply = bus.call_method(Some("org.freedesktop.UPower"), path.as_str(), Some("org.freedesktop.UPower.Device"), "GetHistory", &("rate", secs, points)).await;
    reply.ok().and_then(|m| m.body().deserialize::<Vec<(u32, f64, u32)>>().ok()).map(discharging).unwrap_or_default()
}

fn parse_loadavg(s: &str) -> [f32; 3] {
    let mut it = s.split_whitespace().map(|x| x.parse().unwrap_or(0.0));
    [it.next().unwrap_or(0.0), it.next().unwrap_or(0.0), it.next().unwrap_or(0.0)]
}

/// (used, total) kB, used being what isn't available.
fn parse_meminfo(s: &str) -> (u64, u64) {
    let field = |k: &str| s.lines().find_map(|l| l.strip_prefix(k)?.trim().trim_end_matches(" kB").trim().parse::<u64>().ok()).unwrap_or(0);
    let (total, avail) = (field("MemTotal:"), field("MemAvailable:"));
    (total.saturating_sub(avail), total)
}

/// (busy, total) ticks of all CPUs, from /proc/stat's `cpu ` line; idle and iowait aren't busy.
fn cpu_ticks(stat: &str) -> (u64, u64) {
    let Some(line) = stat.lines().find(|l| l.starts_with("cpu ")) else { return (0, 0) };
    let n: Vec<u64> = line.split_whitespace().skip(1).filter_map(|x| x.parse().ok()).collect();
    // user nice system idle iowait irq softirq steal guest guest_nice; guests are already in user/nice.
    let total: u64 = n.iter().take(8).sum();
    (total - n.get(3).unwrap_or(&0) - n.get(4).unwrap_or(&0), total)
}

/// A process, from /proc: when it started (boot ticks, which tell a reused pid apart), CPU
/// ticks (user + system) and resident memory.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Proc { pub pid: u32, pub ppid: u32, pub comm: String, pub cgroup: String, pub start: u64, pub ticks: u64, pub rss_kb: u64 }

/// What a process counts toward: an app (with everything it started), a job in a terminal
/// tab, or a service.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Kind { App, Job, Service }

/// The process heading `pid`'s group, and the group's kind; None for kernel threads. Apps are
/// what the `compositor` (its pid) or systemd launched; a scope something else made (a
/// terminal's tab) holds jobs.
fn group_key(procs: &HashMap<u32, Proc>, pid: u32, compositor: u32) -> Option<(u32, Kind)> {
    let p = procs.get(&pid)?;
    if pid == 2 || p.ppid == 2 { return None; }
    // Up while the parent is in the same cgroup, stopping under init and the compositor.
    let mut path = vec![pid];
    let mut at = p;
    // Capped: /proc isn't read atomically, so a reused pid can make a parent loop.
    while let Some(up) = procs.get(&at.ppid).filter(|u| u.pid != 1 && u.cgroup == p.cgroup && path.len() < 64) {
        if at.pid == compositor || up.pid == compositor { break; }
        path.push(up.pid);
        at = up;
    }
    let top = *path.last()?;
    if p.cgroup.ends_with(".service") { return Some((top, Kind::Service)); }
    // Who started the group: the compositor, systemd (its own scope), or a terminal.
    let launcher = procs.get(&procs[&top].ppid);
    let by_system = launcher.is_none_or(|l| l.pid == 1 || l.pid == compositor || l.cgroup.ends_with("/init.scope") || l.cgroup == p.cgroup);
    Some(if by_system { (top, Kind::App) }
        // A terminal tab's scope: `top` is its shell, and each command under the shell is a job.
        else { (if path.len() >= 2 { path[path.len() - 2] } else { top }, Kind::Job) })
}

/// The compositor's pid: the peer of a fresh connection to the Wayland socket. 0 if unknown.
fn compositor() -> u32 {
    static PID: std::sync::OnceLock<u32> = std::sync::OnceLock::new();
    *PID.get_or_init(|| {
        let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
        let path = if display.starts_with('/') { display.into() }
            else { std::path::PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR").unwrap_or_default()).join(display) };
        let Ok(sock) = std::os::unix::net::UnixStream::connect(path) else { return 0 };
        let mut cred = libc::ucred { pid: 0, uid: 0, gid: 0 };
        let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
        // SAFETY: SO_PEERCRED fills the ucred we hand it, of the length we pass.
        let ok = unsafe { libc::getsockopt(std::os::fd::AsRawFd::as_raw_fd(&sock), libc::SOL_SOCKET, libc::SO_PEERCRED, (&raw mut cred).cast(), &mut len) };
        if ok == 0 { cred.pid.max(0) as u32 } else { 0 }
    })
}

#[derive(Debug, PartialEq)]
struct Stat { ppid: u32, comm: String, ticks: u64, start: u64 }

/// A /proc/[pid]/stat line; the comm is in parentheses and may hold any byte.
fn parse_stat(line: &str) -> Option<Stat> {
    let (head, rest) = line.rsplit_once(')')?;
    let comm = head.split_once('(')?.1.to_owned();
    let f: Vec<&str> = rest.split_whitespace().collect();
    let n = |i: usize| f.get(i)?.parse::<u64>().ok();
    // After the comm: state, ppid, … utime (12th), stime (13th), … starttime (20th).
    Some(Stat { ppid: n(1)? as u32, comm, ticks: n(11)? + n(12)?, start: n(19)? })
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct AppRow { pub name: String, pub icon: Option<String>, pub cpu: f32, pub rss_kb: u64, /** Estimated, see `attribute`; None when it can't be. */ pub watts: Option<f32> }

/// The `n` groups using the most CPU between `prev` (pid → (start, ticks)) and `now`, `secs`
/// apart, as % of one core.
fn top_apps(prev: &HashMap<u32, (u64, u64)>, now: &HashMap<u32, Proc>, secs: f32, n: usize, compositor: u32) -> Vec<AppRow> {
    // SAFETY: sysconf only reads a constant.
    let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f32;
    let mut groups: HashMap<(u32, Kind), (u64, u64)> = HashMap::new();
    for p in now.values() {
        let Some(key) = group_key(now, p.pid, compositor) else { continue };
        let g = groups.entry(key).or_default();
        // A process not in `prev` (or a reused pid) started inside the window: all its time counts.
        // Processes that exited inside it are lost.
        g.0 += prev.get(&p.pid).filter(|q| q.0 == p.start).map_or(p.ticks, |q| p.ticks.saturating_sub(q.1));
        g.1 += p.rss_kb;
    }
    // Name only the likely winners: naming reads a command line and matches desktop entries.
    // Groups that merge by name (two terminal windows) are among them, as the busiest are.
    let mut groups: Vec<_> = groups.into_iter().collect();
    groups.sort_by(|a, b| b.1.0.cmp(&a.1.0).then(b.1.1.cmp(&a.1.1)));
    groups.truncate(n * 3);
    let mut rows: Vec<AppRow> = Vec::new();
    for ((root, kind), (ticks, rss_kb)) in groups {
        let (name, icon) = name_of(now, root, kind);
        let cpu = ticks as f32 / hz / secs.max(0.001) * 100.0;
        match rows.iter_mut().find(|r| r.name == name) {
            Some(r) => { r.cpu += cpu; r.rss_kb += rss_kb; }
            None => rows.push(AppRow { name, icon, cpu, rss_kb, watts: None }),
        }
    }
    rows.sort_by(|a, b| b.cpu.total_cmp(&a.cpu).then(b.rss_kb.cmp(&a.rss_kb)));
    rows.truncate(n);
    rows
}

/// A process name without NixOS's wrapper dressing: `.zen-beta-wrapp` → `zen-beta`.
fn clean(comm: &str) -> String {
    let c = comm.strip_prefix('.').unwrap_or(comm);
    c.strip_suffix("-wrapped").or_else(|| c.strip_suffix("-wrapp")).unwrap_or(c).to_owned()
}

/// Names and icons by group root, so each app's command line and desktop entry are looked up
/// once per opening of the panel.
static NAMES: std::sync::Mutex<Option<HashMap<(u32, Kind), (String, Option<String>)>>> = std::sync::Mutex::new(None);

/// A group's name and icon (a path or an icon name for `hub::app_icons`).
fn name_of(procs: &HashMap<u32, Proc>, root: u32, kind: Kind) -> (String, Option<String>) {
    if let Some(hit) = NAMES.lock().unwrap().get_or_insert_default().get(&(root, kind)) { return hit.clone(); }
    let comm = procs.get(&root).map_or_else(String::new, |p| clean(&p.comm));
    let app = |pid: u32, fallback: String| {
        let launcher = std::fs::read(format!("/proc/{pid}/cmdline")).map(|c| crate::notify::apps::launcher_names(&c)).unwrap_or_default();
        let Some(first) = launcher.first() else { return (fallback, None) };
        let who = crate::notify::apps::identify(&crate::notify::apps::entries(), first, "", None, "", &launcher);
        (who.app, who.icon.map(|p| p.to_string_lossy().into_owned()))
    };
    let out = match kind {
        Kind::App => app(root, comm),
        // The terminal's icon: the tab's shell's parent.
        Kind::Job => {
            let shell = procs.get(&root).and_then(|p| procs.get(&p.ppid)).filter(|sh| sh.cgroup == procs[&root].cgroup).map_or(root, |sh| sh.pid);
            let term = procs.get(&shell).map(|sh| sh.ppid).filter(|&t| t > 1);
            (comm, term.and_then(|t| app(t, String::new()).1))
        }
        Kind::Service => {
            let unit = procs.get(&root).and_then(|p| p.cgroup.rsplit('/').next()).and_then(|u| u.strip_suffix(".service"));
            (unit.map_or(comm, str::to_owned), None)
        }
    };
    NAMES.lock().unwrap().get_or_insert_default().insert((root, kind), out.clone());
    out
}

/// Each process's stat, by pid.
fn each_stat(mut f: impl FnMut(u32, &std::path::Path, Stat)) {
    for e in std::fs::read_dir("/proc").into_iter().flatten().flatten() {
        let Some(pid) = e.file_name().to_str().and_then(|n| n.parse::<u32>().ok()) else { continue };
        let dir = e.path();
        if let Some(st) = std::fs::read_to_string(dir.join("stat")).ok().as_deref().and_then(parse_stat) { f(pid, &dir, st); }
    }
}

/// Every process's (start, ticks): all a snapshot keeps.
fn read_ticks() -> HashMap<u32, (u64, u64)> {
    let mut out = HashMap::new();
    each_stat(|pid, _, st| { out.insert(pid, (st.start, st.ticks)); });
    out
}

/// Every process in /proc.
fn read_procs() -> HashMap<u32, Proc> {
    // SAFETY: sysconf only reads a constant.
    let page_kb = (unsafe { libc::sysconf(libc::_SC_PAGESIZE) }.max(4096) / 1024) as u64;
    let mut out = HashMap::new();
    each_stat(|pid, dir, Stat { ppid, comm, ticks, start }| {
        let cgroup = std::fs::read_to_string(dir.join("cgroup")).unwrap_or_default().lines().find(|l| l.starts_with("0::")).unwrap_or("").to_owned();
        let rss_kb = std::fs::read_to_string(dir.join("statm")).ok().and_then(|s| s.split_whitespace().nth(1)?.parse::<u64>().ok()).unwrap_or(0) * page_kb;
        out.insert(pid, Proc { pid, ppid, comm, cgroup, start, ticks, rss_kb });
    });
    out
}

/// The sampler's generation: opening starts one, closing ends it; a sampler thread runs, and
/// publishes, only while its generation is current.
static GEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

fn next_gen() -> u64 { GEN.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1 }
/// Ends sampler `g` if it's still the current one; false if a newer one has started since.
fn stop_sampler(g: u64) -> bool {
    use std::sync::atomic::Ordering::SeqCst;
    GEN.compare_exchange(g, g + 1, SeqCst, SeqCst).is_ok()
}
fn is_current(g: u64) -> bool { GEN.load(std::sync::atomic::Ordering::SeqCst) == g }

/// What the open panel shows.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Stats {
    pub flow: Flow,
    /// (time, W), oldest first.
    pub history: Vec<(u32, f32)>,
    /// All CPUs, 0–100.
    pub cpu: f32,
    pub load: [f32; 3],
    /// (used, total) kB.
    pub mem: (u64, u64),
    pub apps: Vec<AppRow>,
    /// The minutes the apps list covers.
    pub apps_minutes: u32,
}

/// Rounds to what the panel shows, so a sample that only moved past the shown precision doesn't
/// redraw the bars.
fn shown(x: f32, step: f32) -> f32 { (x / step).round() * step }

/// Samples every 2 s (the history every 30 s) until the panel closes.
fn start_sampler() -> u64 {
    use std::time::{Duration, Instant};
    /// How often the open panel re-measures the apps (over the last 10 minutes).
    const APPS_EVERY: Duration = Duration::from_secs(60);
    let g = next_gen();
    let _ = std::thread::Builder::new().name("power".into()).spawn(move || {
        let (Some(battery), adapters) = supplies() else { return };
        let bus = crate::rt::block_on(crate::rt::system()).ok();
        let history = |secs, points| bus.as_ref().map_or_else(Vec::new, |bus| crate::rt::block_on(history(bus, &battery, secs, points)));
        // SAFETY: sysconf only reads a constant.
        let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f32;
        let compositor = compositor();
        let mut cpu_prev: Option<(u64, u64)> = None;
        // Without snapshots (headless), the apps list starts from the sampler's own first read.
        let mut own_start: Option<Snap> = None;
        let mut apps: (Option<Instant>, Vec<AppRow>, u32) = (None, Vec::new(), 0);
        // System watts while open, for when UPower's history can't say (on the adapter).
        let (mut system_sum, mut system_n) = (0.0f32, 0u32);
        let mut recent: (Option<Instant>, Vec<(u32, f32)>) = (None, Vec::new());
        // The idle draw, from a day of battery use (5-minute averages), read once per opening.
        let idle = baseline(&history(86_400, 288));
        while is_current(g) {
            if recent.0.is_none_or(|t| t.elapsed() >= Duration::from_secs(30)) { recent = (Some(Instant::now()), history(10_800, 60)); }
            let ticks = cpu_ticks(&std::fs::read_to_string("/proc/stat").unwrap_or_default());
            let cpu = cpu_prev.map_or(0.0, |(busy, total)| ticks.0.saturating_sub(busy) as f32 / ticks.1.saturating_sub(total).max(1) as f32 * 100.0);
            cpu_prev = Some(ticks);
            let mut flow = read_flow(&battery, &adapters);
            if let Some(w) = flow.system_w { system_sum += w; system_n += 1; }
            if apps.0.is_none_or(|t| t.elapsed() >= APPS_EVERY) {
                let procs = read_procs();
                match window_start().or_else(|| own_start.clone()) {
                    Some((at, before, busy)) if at.elapsed() >= Duration::from_millis(500) => {
                        let secs = at.elapsed().as_secs_f32();
                        let mut rows = top_apps(&before, &procs, secs, 5, compositor);
                        let busy_cores = ticks.0.saturating_sub(busy) as f32 / hz / secs;
                        let since = (crate::clock::now() - secs as i64).max(0) as u32;
                        let open_avg = (system_n > 0).then(|| system_sum / system_n as f32);
                        let system = if flow.on_ac { open_avg } else { avg_since(&recent.1, since).or(open_avg) };
                        attribute(&mut rows, busy_cores, system, idle);
                        rows.sort_by(|a, b| b.watts.unwrap_or(0.0).total_cmp(&a.watts.unwrap_or(0.0)).then(b.cpu.total_cmp(&a.cpu)));
                        apps = (Some(Instant::now()), rows, (secs / 60.0).round() as u32);
                    }
                    Some(_) => {}
                    None => own_start = Some((Instant::now(), procs.iter().map(|(pid, p)| (*pid, (p.start, p.ticks))).collect(), ticks.0)),
                }
            }
            flow.battery_w = shown(flow.battery_w, 0.1);
            flow.adapter_w = flow.adapter_w.map(|w| shown(w, 0.1));
            flow.system_w = flow.system_w.map(|w| shown(w, 0.1));
            let (used, total) = parse_meminfo(&std::fs::read_to_string("/proc/meminfo").unwrap_or_default());
            let stats = Stats {
                flow, history: recent.1.clone(), cpu: cpu.round(), apps: apps.1.clone(), apps_minutes: apps.2,
                load: parse_loadavg(&std::fs::read_to_string("/proc/loadavg").unwrap_or_default()).map(|l| shown(l, 0.01)),
                // To a tenth of a GB, as shown.
                mem: (used / 104_858 * 104_858, total),
            };
            crate::hub::app_icons(stats.apps.iter().filter_map(|a| a.icon.as_deref()));
            // Checked under the data lock, so a sampler the panel's closing ended never publishes.
            let changed = {
                let mut d = crate::hub::data();
                if !is_current(g) { return; }
                let new = Some(stats);
                let changed = d.power != new;
                d.power = new;
                changed
            };
            if changed { crate::hub::wake_where(|b| b.power_open); }
            // Until the first list, sample sooner.
            std::thread::sleep(Duration::from_secs(if apps.0.is_none() { 1 } else { 2 }));
        }
    });
    g
}

/// `--power-demo`: samples from startup, for a headless `--snap` of the open panel.
pub fn demo() { DEMO.store(true, std::sync::atomic::Ordering::SeqCst); start_sampler(); }
static DEMO: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn toggle_panel(s: &mut Bar) {
    let open = !s.power_open;
    crate::close_popups(s);
    s.power_open = open;
    // The demo's sampler is already going; a new one's first pass would blank its CPU and apps.
    if open && !DEMO.load(std::sync::atomic::Ordering::SeqCst) { s.power_gen = start_sampler(); }
}

pub fn close(s: &mut Bar) {
    if !s.power_open { return; }
    s.power_open = false;
    // Another monitor's bar may close its panel after this one's opened (`close_popups` reaches
    // other bars later): then its sampler is no longer the current one, and stays stopped.
    if stop_sampler(s.power_gen) {
        NAMES.lock().unwrap().take();
        crate::hub::put(|d| &mut d.power, None);
    }
}

// The panel.

use rune::{El, TextStyle, col, el, row, text};

use crate::wifi::{TITLE, muted, panel_box, row_base, section, sep};
use crate::{Data, LABEL, accent, app_icon, c, fg};

const SMALL: TextStyle = TextStyle::new(11.0, 400.0);

fn watts(w: Option<f32>) -> String { w.map_or_else(|| "—".into(), |w| format!("{w:.1} W")) }

fn bytes(kb: u64) -> String {
    let gb = kb as f32 / 1024.0 / 1024.0;
    if gb >= 1.0 { format!("{gb:.1} GB") } else { format!("{} MB", kb / 1024) }
}

fn adapter_color() -> rune::Color { c("#4f8fd6") }
fn battery_color() -> rune::Color { c("#e3a33b") }

const SANKEY_W: f32 = 120.0;
const SANKEY_H: f32 = 78.0;
const LABEL_W: f32 = 74.0;
/// Columns each curve is drawn with.
const STEPS: usize = 24;

/// The polygon between `top(u)` and `bottom(u)` across the diagram.
fn strip(top: impl Fn(f32) -> f32, bottom: impl Fn(f32) -> f32) -> Vec<[f32; 2]> {
    let us: Vec<f32> = (0..=STEPS).map(|i| i as f32 / STEPS as f32).collect();
    us.iter().map(|&u| [u * SANKEY_W, top(u)]).chain(us.iter().rev().map(|&u| [u * SANKEY_W, bottom(u)])).collect()
}

/// AlDente's power flow as a Sankey: sources (adapter, battery) on the left, consumers (system,
/// battery while charging) on the right, each link as thick as its watts.
fn sankey(f: &Flow) -> El {
    let w = links(f);
    let total: f32 = w.iter().sum();
    // Thickness tracks real watts (full height at 45 W or the total, whichever is more), in
    // half points, so small wobbles don't redraw it.
    let k = (SANKEY_H - 14.0) / total.max(45.0);
    let h = |x: f32| if x > 0.05 { ((x * k).max(2.0) * 2.0).round() / 2.0 } else { 0.0 };
    let (a2s, a2b, b2s) = (h(w[0]), h(w[1]), h(w[2]));
    const GAP: f32 = 12.0;
    // Stacks a side's two nodes, centred: each one's top.
    let stack = |a: f32, b: f32| { let gap = if a > 0.0 && b > 0.0 { GAP } else { 0.0 }; let top = ((SANKEY_H - a - b - gap) / 2.0).round();
        (top, top + a + gap) };
    let (adapter_y, battery_y) = stack(a2s + a2b, b2s);
    let (system_y, charge_y) = stack(a2s + b2s, a2b);
    // The adapter's links go to the system's top.
    let ribbons: Vec<(f32, f32, f32, rune::Color)> = [(adapter_y, system_y, a2s, adapter_color()), (adapter_y + a2s, charge_y, a2b, adapter_color()),
        (battery_y, system_y + a2s, b2s, battery_color())].into_iter().filter(|r| r.2 > 0.0).collect();
    let mut shape = rune::Shape::new();
    for &(y0, y1, th, col) in &ribbons {
        shape = shape.fill(strip(|u| ease(y0, y1, u), |u| ease(y0, y1, u) + th), col.alpha(0.45));
    }
    let bar = |x: f32, y: f32, hh: f32| vec![[x, y], [x + 3.0, y], [x + 3.0, y + hh], [x, y + hh]];
    for (x, y, hh, col) in [(0.0, adapter_y, a2s + a2b, adapter_color()), (0.0, battery_y, b2s, battery_color()),
        (SANKEY_W - 3.0, system_y, a2s + b2s, c("#d8d8d8")), (SANKEY_W - 3.0, charge_y, a2b, battery_color())] {
        if hh > 0.0 { shape = shape.fill(bar(x, y, hh), col); }
    }
    // A new key per shape: a change crossfades on the renderer's own transition, with no
    // frames of ours.
    let canvas = rune::canvas(shape).key(format!("ribbons-{a2s}-{a2b}-{b2s}").as_str()).absolute(LABEL_W + 8.0, 0.0)
        .size(SANKEY_W, SANKEY_H).transition(rune::Transition::opacity());
    // Labels beside each node, at its middle.
    let label = |key: &str, x: f32, y: f32, name: &str, value: String, right: bool| {
        let c = col().key(key).absolute(x, (y - 15.0).clamp(0.0, SANKEY_H - 30.0)).w(LABEL_W).gap(1.0)
            .child(text(name.to_owned()).key("name").font(SMALL).color(muted()))
            .child(text(value).key("value").font(LABEL).color(fg()));
        if right { c.items_start() } else { c.items_end() }
    };
    let mut out = el().key("sankey").w_full().h(SANKEY_H).my(6.0).child(canvas);
    let rx = LABEL_W + 8.0 + SANKEY_W + 8.0;
    // A side showing two labels keeps them apart.
    let pair = |both: bool, a: f32, b: f32| if both { apart(a, b) } else { (a, b) };
    let (adapter_y, battery_y) = pair(f.on_ac && b2s > 0.0, adapter_y + (a2s + a2b) / 2.0, battery_y + b2s / 2.0);
    let (system_y, charge_y) = pair(a2b > 0.0, system_y + (a2s + b2s) / 2.0, charge_y + a2b / 2.0);
    if f.on_ac { out = out.child(label("adapter", 0.0, adapter_y, "Adapter", watts(f.adapter_w), false)); }
    if b2s > 0.0 || !f.on_ac { out = out.child(label("battery", 0.0, battery_y, "Battery", watts(Some(-f.battery_w.min(0.0))), false)); }
    out = out.child(label("system", rx, system_y, "System", watts(f.system_w), true));
    if a2b > 0.0 { out = out.child(label("charge", rx, charge_y, "Battery", watts(Some(f.battery_w.max(0.0))), true)); }
    out
}

fn graph(h: &[(u32, f32)]) -> El {
    if h.is_empty() { return text("No battery use in the last 3 h").key("graph-empty").font(SMALL).color(muted()).px(6.0).py(4.0); }
    let max = h.iter().map(|p| p.1).fold(1.0f32, f32::max);
    let n = h.len() as f32;
    let w = ((300.0 - 24.0 - (n - 1.0)) / n).max(1.0);
    let mut bars = row().key("graph").w_full().h(56.0).px(6.0).gap(1.0).items_end();
    for (i, (_, v)) in h.iter().enumerate() {
        bars = bars.child(el().key(format!("bar-{i}").as_str()).w(w).h((v / max * 56.0).max(2.0)).radius(1.5).fill(accent().alpha(0.85)));
    }
    bars
}

/// A label, a thin meter filled to `frac`, and a value.
fn meter(key: &str, label: &str, frac: f32, value: String) -> El {
    let fill = el().key("fill").w_frac(frac.clamp(0.0, 1.0)).h_full().radius(3.0).fill(accent());
    row_base(key)
        .child(text(label.to_owned()).key("label").font(LABEL).color(fg()).w(56.0))
        .child(el().key("track").grow(1.0).h(6.0).radius(3.0).fill(c("#ffffff").alpha(0.18)).child(fill))
        .child(text(value).key("value").font(LABEL).color(fg()).w(86.0))
}

fn app_row(d: &Data, a: &AppRow) -> El {
    row_base(&format!("app-{}", a.name))
        // A fixed column: the fallback glyph is narrower than an icon.
        .child(el().key("icon").w(18.0).center().child(app_icon(d, a.icon.as_deref(), 18.0, "img".into())))
        .child(text(a.name.clone()).key("name").font(LABEL).color(fg()).grow(1.0).truncate())
        .child(text(format!("{:.0}% · {}", a.cpu, bytes(a.rss_kb))).key("detail").font(SMALL).color(muted()))
        .child(text(a.watts.map_or_else(|| "—".into(), |w| format!("{w:.1} W"))).key("watts").font(LABEL).color(fg()).w(48.0).align(rune::Align::End))
}

pub fn panel(s: &Bar, d: &Data) -> Option<El> {
    if !s.power_open { return None; }
    let b = d.battery.as_ref()?;
    let st = d.power.clone().unwrap_or_default();
    let time = match (&b.time, b.charging) {
        (Some(t), true) => format!("{t} until full"),
        (Some(t), false) => format!("{t} remaining"),
        (None, true) => "Charging".into(),
        (None, false) => if st.flow.on_ac { "On power adapter".into() } else { String::new() },
    };
    let avg = (!st.history.is_empty()).then(|| st.history.iter().map(|p| p.1).sum::<f32>() / st.history.len() as f32);
    let mut rows = vec![
        row_base("title").pt(6.0).child(text("Battery").key("title").font(TITLE).color(fg()).grow(1.0))
            .child(text(format!("{}%", b.percent)).key("pct").font(TITLE).color(fg())),
        text(time).key("time").font(SMALL).color(muted()).px(6.0),
        sankey(&st.flow),
        sep("graph-sep"),
        row().key("graph-head").w_full().items_center()
            .child(section("graph-title", "Power · last 3 h").grow(1.0))
            .child(text(avg.map_or_else(String::new, |a| format!("avg {a:.1} W"))).key("avg").font(SMALL).color(muted()).px(6.0).pt(8.0).pb(2.0)),
        graph(&st.history),
        sep("cpu-sep"),
        meter("cpu", "CPU", st.cpu / 100.0, format!("{:.0}%", st.cpu)),
        text(format!("Load {:.2} · {:.2} · {:.2}", st.load[0], st.load[1], st.load[2])).key("load").font(SMALL).color(muted()).px(6.0).pl(72.0),
        meter("mem", "Memory", st.mem.0 as f32 / st.mem.1.max(1) as f32,
            format!("{:.1} / {:.0} GB", st.mem.0 as f32 / 1048576.0, st.mem.1 as f32 / 1048576.0)),
        sep("apps-sep"),
        section("apps-title", &if st.apps_minutes > 0 { format!("Apps · estimated power, last {} min", st.apps_minutes) } else { "Apps · estimated power".into() }),
    ];
    if st.apps.is_empty() { rows.push(text("Measuring…").key("measuring").font(SMALL).color(muted()).px(6.0).py(4.0)); }
    rows.extend(st.apps.iter().map(|a| app_row(d, a)));
    Some(panel_box(s, "power-panel", rows))
}

/// The Sankey's links in watts: [adapter → system, adapter → battery, battery → system].
fn links(f: &Flow) -> [f32; 3] {
    let charge = f.battery_w.max(0.0);
    let drain = (-f.battery_w).max(0.0);
    let from_adapter = if f.on_ac { f.adapter_w.map_or(0.0, |a| (a - charge).max(0.0)) } else { 0.0 };
    [from_adapter, if f.on_ac { charge } else { 0.0 }, drain]
}

/// Two labels' middles on one side, the upper first, moved apart enough not to overlap and
/// kept inside the diagram.
fn apart(upper: f32, lower: f32) -> (f32, f32) {
    const H: f32 = 32.0;
    if lower - upper >= H { return (upper, lower); }
    let m = ((upper + lower) / 2.0).clamp(15.0 + H / 2.0, SANKEY_H - 15.0 - H / 2.0);
    (m - H / 2.0, m + H / 2.0)
}

/// A band's top at `u` across: eased between its ends, as a Sankey's curves are.
fn ease(y0: f32, y1: f32, u: f32) -> f32 { y0 + (y1 - y0) * u * u * (3.0 - 2.0 * u) }

/// Each app's estimated watts: its share of the busy CPU time (`busy_cores`, averaged over the
/// same window as `AppRow::cpu`) of what the system draws above `baseline_w`.
// ponytail: CPU time only; GPU work (video decode) and the screen aren't charged to apps.
// Per-client GPU time from /proc/*/fdinfo could refine it if the ranking misleads.
fn attribute(rows: &mut [AppRow], busy_cores: f32, system_w: Option<f32>, baseline_w: Option<f32>) {
    let spare = system_w.zip(baseline_w).map(|(s, b)| (s - b).max(0.0));
    for r in rows {
        r.watts = spare.map(|spare| if busy_cores > 0.0 { spare * (r.cpu / 100.0 / busy_cores).min(1.0) } else { 0.0 });
    }
}

/// The idle draw: the lowest UPower recorded on battery in `history`.
fn baseline(history: &[(u32, f32)]) -> Option<f32> {
    // Under half a watt is a glitch, not a laptop's draw.
    history.iter().map(|p| p.1).filter(|w| *w >= 0.5).reduce(f32::min)
}

/// The mean of the `history` points at or after `since` (unix seconds).
fn avg_since(history: &[(u32, f32)], since: u32) -> Option<f32> {
    let w: Vec<f32> = history.iter().filter(|p| p.0 >= since).map(|p| p.1).collect();
    (!w.is_empty()).then(|| w.iter().sum::<f32>() / w.len() as f32)
}

/// How far back the apps list looks.
const APPS_WINDOW: std::time::Duration = std::time::Duration::from_secs(600);

/// Process CPU times taken every 5 minutes, panel open or not, so the apps list can cover the
/// last 10 minutes: (when, pid → (start, ticks), busy CPU ticks).
type Snap = (std::time::Instant, HashMap<u32, (u64, u64)>, u64);
static SNAPS: std::sync::Mutex<std::collections::VecDeque<Snap>> = std::sync::Mutex::new(std::collections::VecDeque::new());

/// Starts the snapshots, on a machine with a battery: one /proc/*/stat pass every 5 minutes.
pub fn start() {
    if supplies().0.is_none() { return; }
    let _ = std::thread::Builder::new().name("power-snap".into()).spawn(|| loop {
        let snap = (std::time::Instant::now(), read_ticks(), cpu_ticks(&std::fs::read_to_string("/proc/stat").unwrap_or_default()).0);
        let mut q = SNAPS.lock().unwrap();
        q.push_back(snap);
        // Keep 20 minutes: always one at least 10 minutes old once the bar has run that long.
        while q.len() > 1 && q[0].0.elapsed() > APPS_WINDOW * 2 { q.pop_front(); }
        drop(q);
        std::thread::sleep(APPS_WINDOW / 2);
    });
}

/// The snapshot to measure the apps from: the newest at least 10 minutes old, else the oldest.
fn window_start() -> Option<Snap> {
    let q = SNAPS.lock().unwrap();
    q.iter().rev().find(|s| s.0.elapsed() >= APPS_WINDOW).or(q.front()).cloned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test] fn flow_discharging() {
        let f = flow("Discharging", 13_657_000, &[(false, 0, 0)]);
        assert_eq!((f.on_ac, f.adapter_w), (false, None));
        assert!((f.battery_w + 13.657).abs() < 0.01 && (f.system_w.unwrap() - 13.657).abs() < 0.01);
    }

    #[test] fn flow_charging() {
        let f = flow("Charging", 20_000_000, &[(true, 20_000_000, 3_000_000)]);
        assert!((f.adapter_w.unwrap() - 60.0).abs() < 0.01 && (f.battery_w - 20.0).abs() < 0.01 && (f.system_w.unwrap() - 40.0).abs() < 0.01);
    }

    #[test] fn flow_adapter_reading_below_charge_rate() {
        // UCSI can report a stale 5 V × 3 A while a 60 W contract charges at 43 W.
        let f = flow("Charging", 43_315_000, &[(true, 5_000_000, 3_000_000)]);
        assert_eq!((f.on_ac, f.adapter_w, f.system_w), (true, None, None));
    }

    #[test] fn flow_ac_unknown_current() {
        let f = flow("Not charging", 0, &[(true, 20_000_000, 0)]);
        assert_eq!((f.on_ac, f.adapter_w, f.system_w), (true, None, None));
    }

    #[test] fn history() {
        // Only discharging points (state 2): a charge rate isn't what the system draws.
        let points = vec![(1793870526, 15.32, 0), (1793869664, 17.9, 2), (1793868401, 20.6, 2), (1793868000, 3.1, 1)];
        assert_eq!(discharging(points), vec![(1793868401, 20.6), (1793869664, 17.9)]);
    }

    #[test] fn supply_discovery() {
        let s = |name: &str, kind: &str, scope: &str| (name.to_owned(), kind.to_owned(), scope.to_owned());
        // A mouse's battery (scope Device) isn't the laptop's.
        let found = pick_supplies(vec![s("hidpp_battery_0", "Battery", "Device"), s("BAT1", "Battery", ""), s("AC", "Mains", ""),
            s("ucsi-source-psy-USBC000:001", "USB", "System"), s("hidpp_usb", "USB", "Device")]);
        assert_eq!(found, (Some("BAT1".to_owned()), vec!["AC".to_owned(), "ucsi-source-psy-USBC000:001".to_owned()]));
        assert_eq!(pick_supplies(vec![s("AC", "Mains", "")]).0, None);
    }

    #[test] fn procfs() {
        assert_eq!(parse_loadavg("1.61 1.55 1.74 2/1228 59752\n"), [1.61, 1.55, 1.74]);
        assert_eq!(parse_meminfo("MemTotal:  32000000 kB\nMemFree: 1 kB\nMemAvailable: 20000000 kB\n"), (12_000_000, 32_000_000));
        assert_eq!(cpu_ticks("cpu  100 10 50 800 40 5 5 0 0 0\ncpu0 1 2 3"), (170, 1010));
    }

    #[test] fn grouping() {
        let p = |pid, ppid, comm: &str, cg: &str| (pid, Proc { pid, ppid, comm: comm.into(), cgroup: cg.into(), ..Default::default() });
        let s = "0::/user.slice/user-1000.slice/session-1.scope";
        let tab = "0::/user.slice/user-1000.slice/user@1000.service/kitty-3864-0.scope";
        let svc = "0::/user.slice/user-1000.slice/user@1000.service/app.slice/syncthing.service";
        // An app a launcher put in its own scope (uwsm, app2unit): started by the user's systemd.
        let mgr = "0::/user.slice/user-1000.slice/user@1000.service/init.scope";
        let own = "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-foot-1.scope";
        let m: HashMap<u32, Proc> = [p(1, 0, "systemd", "0::/init.scope"), p(2, 0, "kthreadd", "0::/"), p(9, 2, "kworker", "0::/"),
            p(5, 1, "ly-dm", s), p(10, 5, "compositor", s), p(20, 10, ".zen-beta-wrapp", s), p(21, 20, "Isolated Web Co", s),
            p(30, 10, "kitty", s), p(31, 30, "zsh", tab), p(32, 31, "cargo", tab), p(33, 32, "rustc", tab),
            p(40, 1, "syncthing", svc), p(41, 40, "syncthing", svc), p(50, 1, "systemd", mgr), p(71, 50, "foot", own), p(72, 71, "sh", own)].into();
        let g = |pid| group_key(&m, pid, 10);
        assert_eq!(g(21), Some((20, Kind::App)));
        assert_eq!(g(10), Some((10, Kind::App)));
        assert_eq!(g(30), Some((30, Kind::App)));
        assert_eq!(g(33), Some((32, Kind::Job)));
        assert_eq!(g(31), Some((31, Kind::Job)));
        assert_eq!(g(41), Some((40, Kind::Service)));
        assert_eq!(g(72), Some((71, Kind::App)));
        assert_eq!(g(9), None);
        assert_eq!(g(2), None);
    }

    #[test] fn group_walk_survives_cycle() {
        // A pid reused mid-read can make two processes each other's parent.
        let cg = "0::/user.slice/user-1000.slice/user@1000.service/kitty-1-0.scope";
        let p = |pid, ppid| (pid, Proc { pid, ppid, comm: "x".into(), cgroup: cg.into(), ..Default::default() });
        let m: HashMap<u32, Proc> = [p(60, 61), p(61, 60)].into();
        assert!(group_key(&m, 60, 0).is_some());
    }

    #[test] fn cpu_delta_counts_new_ignores_exited() {
        // Pids past pid_max, so no real /proc entry names them: the name falls back to the comm.
        let s = "0::/user.slice/user-1000.slice/session-1.scope";
        let p = |pid, ppid, comm: &str, start, ticks| (pid, Proc { pid, ppid, comm: comm.into(), cgroup: s.into(), start, ticks, rss_kb: 1000 });
        let now: HashMap<u32, Proc> = [p(4_200_010, 1, "compositor", 1, 0), p(4_200_020, 4_200_010, ".zen-beta-wrapp", 2, 0),
            p(4_200_021, 4_200_020, "Isolated Web Co", 3, 150),
            // 23 started inside the window: all its time counts. 24 reuses an old pid: so does its.
            p(4_200_023, 4_200_020, "Isolated Web Co", 9, 20), p(4_200_024, 4_200_020, "Isolated Web Co", 9, 10)].into();
        // 22 exited inside the window: lost.
        let prev: HashMap<u32, (u64, u64)> = [(4_200_021, (3, 100)), (4_200_022, (4, 500)), (4_200_024, (5, 400))].into();
        let rows = top_apps(&prev, &now, 1.0, 5, 4_200_010);
        assert_eq!(rows[0].name, "zen-beta");
        assert!((rows[0].cpu - 80.0).abs() < 0.01, "{rows:?}");
        assert_eq!(rows[0].rss_kb, 4000);
    }

    #[test] fn proc_stat_line() {
        let line = "4321 (Web (Content) x) S 4000 4321 4321 0 -1 4194560 100 0 0 0 250 70 0 0 20 0 30 0 123 0 0";
        assert_eq!(parse_stat(line), Some(Stat { ppid: 4000, comm: "Web (Content) x".into(), ticks: 320, start: 123 }));
        assert_eq!(parse_stat("bogus"), None);
    }

    #[test] fn sampler_generation() {
        let g1 = next_gen();
        let g2 = next_gen();
        assert!(!is_current(g1) && is_current(g2));
        // Another monitor's panel closing after this one opened leaves this one's sampler.
        assert!(!stop_sampler(g1));
        assert!(is_current(g2));
        assert!(stop_sampler(g2));
        assert!(!is_current(g2));
    }

    #[test] fn sankey_links() {
        let unplugged = flow("Discharging", 13_000_000, &[(false, 0, 0)]);
        assert_eq!(links(&unplugged), [0.0, 0.0, 13.0]);
        let charging = flow("Charging", 20_000_000, &[(true, 20_000_000, 3_000_000)]);
        assert_eq!(links(&charging), [40.0, 20.0, 0.0]);
        // Plugged in, adapter too weak: both feed the system.
        let short = flow("Discharging", 5_000_000, &[(true, 20_000_000, 1_000_000)]);
        assert_eq!(links(&short), [20.0, 0.0, 5.0]);
        // Adapter watts unknown: no adapter → system link, but the battery still shows its charge.
        assert_eq!(links(&flow("Not charging", 0, &[(true, 20_000_000, 0)])), [0.0, 0.0, 0.0]);
        assert_eq!(links(&flow("Charging", 40_000_000, &[(true, 5_000_000, 3_000_000)])), [0.0, 40.0, 0.0]);
    }

    #[test] fn labels_never_overlap() {
        // Same middle (an empty system node above the charge): pushed a label's height apart.
        assert_eq!(apart(30.0, 30.0), (15.0, 47.0));
        // Already apart: untouched. Near an edge: kept inside.
        assert_eq!(apart(10.0, 60.0), (10.0, 60.0));
        assert_eq!(apart(70.0, 72.0), (SANKEY_H - 47.0, SANKEY_H - 15.0));
    }

    #[test] fn energy_estimate() {
        let row = |cpu| AppRow { name: "x".into(), cpu, ..Default::default() };
        let mut rows = [row(100.0), row(300.0), row(0.0)];
        attribute(&mut rows, 2.0, Some(20.0), Some(5.0));
        // 1 of 2 busy cores → half of the 15 W above idle; a share over 1 (sampling skew) caps at all of it.
        assert_eq!(rows.iter().map(|r| r.watts).collect::<Vec<_>>(), [Some(7.5), Some(15.0), Some(0.0)]);
        let mut idle = [row(50.0)];
        attribute(&mut idle, 0.0, Some(4.0), Some(5.0));
        assert_eq!(idle[0].watts, Some(0.0));
        // Unknown system draw or idle baseline (on the adapter): no estimate, not 0 W.
        attribute(&mut idle, 1.0, None, Some(5.0));
        assert_eq!(idle[0].watts, None);
        attribute(&mut idle, 1.0, Some(20.0), None);
        assert_eq!(idle[0].watts, None);
        assert_eq!(baseline(&[(1, 8.0), (2, 0.2), (3, 6.5)]), Some(6.5));
        assert_eq!(baseline(&[]), None);
    }

    #[test] fn history_window() {
        let h = [(100, 30.0), (200, 10.0), (300, 20.0)];
        assert_eq!(avg_since(&h, 150), Some(15.0));
        assert_eq!(avg_since(&h, 400), None);
    }
}
