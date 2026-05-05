// Unix-socket IPC: lets external processes (CLI, bemenu helpers, Quickshell)
// query librepods state and send control commands without going through the
// iced GUI. Wire format is one JSON object per line; the server is push-based
// for `watch` (streams a new Snapshot every time anything changes) and
// request/response for everything else.

use crate::bluetooth::aacp::{AACPManager, ControlCommandIdentifiers};
use crate::media_controller::MediaController;
use log::{debug, error, info, warn};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{Mutex, RwLock, broadcast, mpsc};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PeerInfo {
    pub mac: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    pub owns: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Snapshot {
    pub connected: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mac: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// "off" | "anc" | "transparency" | "adaptive"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    pub conversational_awareness: bool,
    /// 0..=100; None when unknown.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub battery: Option<u8>,
    /// Per-bud / on-head detection. Empty when unknown.
    pub in_ear: Vec<bool>,
    /// Whether this host currently owns audio routing.
    pub owns: bool,
    /// Other Apple-class peers the AirPods firmware is reporting to us.
    /// Excludes our own host.
    pub peers: Vec<PeerInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum Command {
    Status,
    Mode { value: String },
    ConversationalAwareness { value: bool },
    TakeBack,
    Watch,
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
enum Response<'a> {
    Snapshot(&'a Snapshot),
    Ok { ok: bool },
    Err { error: String },
}

#[derive(Clone)]
pub struct IpcBus {
    pub snapshot: Arc<RwLock<Snapshot>>,
    /// Broadcast a () every time the snapshot changes; watch clients use it
    /// as a signal to re-read and stream the snapshot.
    pub change_tx: broadcast::Sender<()>,
    /// Handle to the live AACPManager for the (single) connected AirPods so
    /// the IPC layer can send protocol packets directly. None until a device
    /// connects.
    pub aacp_manager: Arc<Mutex<Option<AACPManager>>>,
    /// Same plumbing the GUI / event loop uses to pipe control commands back
    /// to the AirPods (mode switch, OwnsConnection, conversational awareness).
    pub command_tx: Arc<Mutex<Option<mpsc::UnboundedSender<(ControlCommandIdentifiers, Vec<u8>)>>>>,
    /// Used by the take-back path to flip A2DP back on locally.
    pub media_controller: Arc<Mutex<Option<Arc<Mutex<MediaController>>>>>,
    /// Cached local adapter MAC, needed by the Smart Routing / Hijack packets.
    pub local_mac: Arc<RwLock<Option<String>>>,
}

impl IpcBus {
    pub fn new() -> Self {
        let (change_tx, _) = broadcast::channel::<()>(16);
        IpcBus {
            snapshot: Arc::new(RwLock::new(Snapshot::default())),
            change_tx,
            aacp_manager: Arc::new(Mutex::new(None)),
            command_tx: Arc::new(Mutex::new(None)),
            media_controller: Arc::new(Mutex::new(None)),
            local_mac: Arc::new(RwLock::new(None)),
        }
    }

    /// Update the snapshot via a closure and broadcast a change signal so
    /// watch clients re-read.
    pub async fn update<F>(&self, f: F)
    where
        F: FnOnce(&mut Snapshot),
    {
        {
            let mut snap = self.snapshot.write().await;
            f(&mut snap);
        }
        let _ = self.change_tx.send(());
    }
}

/// Process-wide singleton. Lazily initialized on first access so that any
/// thread/task can call `bus()` without explicit plumbing.
static BUS: std::sync::OnceLock<IpcBus> = std::sync::OnceLock::new();

pub fn bus() -> &'static IpcBus {
    BUS.get_or_init(IpcBus::new)
}

pub fn socket_path() -> PathBuf {
    if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
        return PathBuf::from(dir).join("librepods.sock");
    }
    PathBuf::from("/tmp/librepods.sock")
}

pub async fn start_ipc_server(bus: IpcBus) {
    let path = socket_path();
    if path.exists() {
        let _ = std::fs::remove_file(&path);
    }
    let listener = match UnixListener::bind(&path) {
        Ok(l) => l,
        Err(e) => {
            error!("Failed to bind IPC socket {}: {}", path.display(), e);
            return;
        }
    };
    info!("IPC server listening on {}", path.display());

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let bus = bus.clone();
                tokio::spawn(handle_client(stream, bus));
            }
            Err(e) => {
                warn!("IPC accept error: {}", e);
            }
        }
    }
}

async fn handle_client(stream: UnixStream, bus: IpcBus) {
    let (read_half, mut write_half) = stream.into_split();
    let mut reader = BufReader::new(read_half).lines();

    while let Ok(Some(line)) = reader.next_line().await {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let cmd: Command = match serde_json::from_str(line) {
            Ok(c) => c,
            Err(e) => {
                let _ = write_response(
                    &mut write_half,
                    &Response::Err {
                        error: format!("invalid command: {}", e),
                    },
                )
                .await;
                continue;
            }
        };

        match cmd {
            Command::Status => {
                let snap = bus.snapshot.read().await;
                let _ = write_response(&mut write_half, &Response::Snapshot(&snap)).await;
            }
            Command::Mode { value } => {
                let result = handle_mode(&bus, &value).await;
                let _ = write_response(&mut write_half, &command_response(result)).await;
            }
            Command::ConversationalAwareness { value } => {
                let result = handle_conversational_awareness(&bus, value).await;
                let _ = write_response(&mut write_half, &command_response(result)).await;
            }
            Command::TakeBack => {
                let result = handle_take_back(&bus).await;
                let _ = write_response(&mut write_half, &command_response(result)).await;
            }
            Command::Watch => {
                // Stream the current snapshot first, then push every time the
                // change signal fires.
                let mut rx = bus.change_tx.subscribe();
                let snap = bus.snapshot.read().await.clone();
                if write_response(&mut write_half, &Response::Snapshot(&snap))
                    .await
                    .is_err()
                {
                    return;
                }
                drop(snap);
                loop {
                    match rx.recv().await {
                        Ok(()) => {
                            let snap = bus.snapshot.read().await.clone();
                            if write_response(&mut write_half, &Response::Snapshot(&snap))
                                .await
                                .is_err()
                            {
                                return;
                            }
                        }
                        Err(broadcast::error::RecvError::Lagged(n)) => {
                            debug!("watch client lagged by {}, sending current state", n);
                            let snap = bus.snapshot.read().await.clone();
                            if write_response(&mut write_half, &Response::Snapshot(&snap))
                                .await
                                .is_err()
                            {
                                return;
                            }
                        }
                        Err(broadcast::error::RecvError::Closed) => return,
                    }
                }
            }
        }
    }
}

async fn write_response(
    write_half: &mut tokio::net::unix::OwnedWriteHalf,
    resp: &Response<'_>,
) -> std::io::Result<()> {
    let mut buf = serde_json::to_vec(resp).unwrap_or_default();
    buf.push(b'\n');
    write_half.write_all(&buf).await
}

fn command_response(result: Result<(), String>) -> Response<'static> {
    match result {
        Ok(()) => Response::Ok { ok: true },
        Err(e) => Response::Err { error: e },
    }
}

fn mode_byte(value: &str) -> Option<u8> {
    match value {
        "off" => Some(0x01),
        "noise_cancellation" | "nc" | "anc" => Some(0x02),
        "transparency" | "trans" => Some(0x03),
        "adaptive" => Some(0x04),
        _ => None,
    }
}

async fn handle_mode(bus: &IpcBus, value: &str) -> Result<(), String> {
    let byte = mode_byte(value).ok_or_else(|| format!("unknown mode: {}", value))?;
    let tx = bus.command_tx.lock().await;
    let tx = tx
        .as_ref()
        .ok_or_else(|| "no AirPods currently connected".to_string())?;
    tx.send((ControlCommandIdentifiers::ListeningMode, vec![byte]))
        .map_err(|e| format!("send failed: {}", e))?;
    Ok(())
}

async fn handle_conversational_awareness(bus: &IpcBus, value: bool) -> Result<(), String> {
    let tx = bus.command_tx.lock().await;
    let tx = tx
        .as_ref()
        .ok_or_else(|| "no AirPods currently connected".to_string())?;
    tx.send((
        ControlCommandIdentifiers::ConversationDetectConfig,
        vec![if value { 0x01 } else { 0x02 }],
    ))
    .map_err(|e| format!("send failed: {}", e))?;
    Ok(())
}

async fn handle_take_back(bus: &IpcBus) -> Result<(), String> {
    // Snapshot what we need under the locks, then drop the locks before any
    // long-awaiting send_* calls (which themselves re-lock the AACP state).
    let aacp_manager = {
        let guard = bus.aacp_manager.lock().await;
        guard
            .as_ref()
            .ok_or_else(|| "no AirPods currently connected".to_string())?
            .clone()
    };
    let local_mac = bus
        .local_mac
        .read()
        .await
        .clone()
        .ok_or_else(|| "local MAC not yet known".to_string())?;
    let target_mac = {
        let state = aacp_manager.state.lock().await;
        state
            .connected_devices
            .iter()
            .find(|d| d.mac != local_mac)
            .map(|d| d.mac.clone())
    };
    let target_mac = target_mac.ok_or_else(|| "no other peer to take audio from".to_string())?;

    let tx_lock = bus.command_tx.lock().await;
    if let Some(tx) = tx_lock.as_ref() {
        let _ = tx.send((ControlCommandIdentifiers::OwnsConnection, vec![0x01]));
    }
    drop(tx_lock);

    {
        let mc_lock = bus.media_controller.lock().await;
        if let Some(mc) = mc_lock.as_ref() {
            let controller = mc.lock().await;
            controller.activate_a2dp_profile().await;
        }
    }

    aacp_manager
        .send_media_information(&local_mac, &target_mac, true)
        .await
        .map_err(|e| format!("send_media_information failed: {}", e))?;
    aacp_manager
        .send_smart_routing_show_ui(&target_mac)
        .await
        .map_err(|e| format!("send_smart_routing_show_ui failed: {}", e))?;
    aacp_manager
        .send_hijack_request(&target_mac)
        .await
        .map_err(|e| format!("send_hijack_request failed: {}", e))?;
    Ok(())
}
