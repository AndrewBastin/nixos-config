//! StatusNotifierItem host (and watcher, when no one else runs one) through `system-tray`,
//! replacing Quickshell's SystemTray service. Clicks come back on a channel.

use std::sync::OnceLock;

use std::collections::HashMap;

use system_tray::client::{ActivateRequest, Client, Event, UpdateEvent};
use system_tray::menu::TrayMenu;
use tokio::sync::mpsc;

use crate::hub;

#[derive(Clone)]
pub struct Item {
    /// The item's bus address, which `system-tray` keys items by.
    pub address: String,
    pub id: String,
    pub title: String,
    pub icon: Option<rune::Image>,
    pub item_is_menu: bool,
    pub menu_path: Option<String>,
    pub menu: Option<TrayMenu>,
}

static REQUESTS: OnceLock<mpsc::UnboundedSender<ActivateRequest>> = OnceLock::new();

pub fn activate(req: ActivateRequest) {
    if let Some(tx) = REQUESTS.get() { let _ = tx.send(req); }
}

/// The tray item the bar leaves out: nm-applet keeps running as NetworkManager's password
/// agent, and the Wi-Fi item replaces its icon.
const HIDDEN: &str = "nm-applet";

/// Themed icons found so far, by (name, theme path): finding one walks the icon directories.
type IconCache = HashMap<(String, Option<String>), Option<rune::Image>>;

fn snapshot(client: &Client, icons: &mut IconCache) -> Vec<Item> {
    let items = client.items();
    let items = items.lock().unwrap();
    let mut out: Vec<Item> = items.iter().filter(|(_, (item, _))| item.id != HIDDEN).map(|(address, (item, menu))| {
        let icon_name = item.icon_name.clone().unwrap_or_default();
        let themed = (!icon_name.is_empty()).then(|| icons.entry((icon_name.clone(), item.icon_theme_path.clone())).or_insert_with(|| {
            crate::sources::icon_path(&icon_name, item.icon_theme_path.as_deref()).map(|p| hub::images().file(p, 16.0, 2.0))
        }).clone()).flatten();
        let icon = themed
            .or_else(|| {
                let px = item.icon_pixmap.as_ref()?.iter().max_by_key(|p| p.width)?;
                // ARGB32 in network byte order to straight RGBA.
                let rgba: Vec<u8> = px.pixels.chunks_exact(4).flat_map(|c| [c[1], c[2], c[3], c[0]]).collect();
                (rgba.len() == (px.width * px.width * 4) as usize).then(|| hub::images().rgba(px.width as u32, px.width as u32, rgba))
            });
        Item {
            address: address.clone(), id: item.id.clone(), title: item.title.clone().unwrap_or_default(), icon,
            item_is_menu: item.item_is_menu, menu_path: item.menu.clone(), menu: menu.clone(),
        }
    }).collect();
    out.sort_by(|a, b| a.id.cmp(&b.id));
    out
}

pub fn start() {
    std::thread::spawn(|| {
        let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        rt.block_on(async {
            let client = match Client::new().await {
                Ok(c) => c,
                Err(e) => return eprintln!("andrew-bar: tray: {e}"),
            };
            let (tx, mut requests) = mpsc::unbounded_channel();
            let _ = REQUESTS.set(tx);
            let mut events = client.subscribe();
            let mut icons = IconCache::new();
            let items = snapshot(&client, &mut icons);
            hub::set(|d| d.tray = items);
            loop {
                tokio::select! {
                    ev = events.recv() => {
                        let ev = match ev {
                            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                            Err(_) => None,
                            Ok(ev) => Some(ev),
                        };
                        // Only what the bar shows: the icon, title and menu of a shown item.
                        if let Some(Event::Update(address, update)) = &ev {
                            let shown = hub::data().tray.iter().any(|i| &i.address == address);
                            if !shown || matches!(update, UpdateEvent::Tooltip(_) | UpdateEvent::Status(_)
                                | UpdateEvent::OverlayIcon(_) | UpdateEvent::AttentionIcon(_)) { continue; }
                        }
                        let items = snapshot(&client, &mut icons);
                        hub::set(|d| d.tray = items);
                    }
                    Some(req) = requests.recv() => {
                        if let Err(e) = client.activate(req).await { eprintln!("andrew-bar: tray activate: {e}"); }
                    }
                }
            }
        });
    });
}
