use clap::Parser;
use hyprland::event_listener::EventListener;
use hyprland::shared::{HyprData, HyprDataActiveOptional};
use lru::LruCache;
use serde::Serialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::num::NonZeroUsize;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use walkdir::WalkDir;

#[derive(Parser)]
#[command(name = "hyprland-info")]
#[command(about = "Hyprland workspace and window information tool")]
struct Args {
    #[arg(long, help = "Monitor workspace and window state, output JSON")]
    monitor: bool,
}

type IconCache = Rc<RefCell<LruCache<(String, String), Option<String>>>>;

#[derive(Serialize)]
struct WorkspaceState {
    monitors: HashMap<String, MonitorInfo>,
    active_window: Option<ActiveWindowInfo>,
}

#[derive(Serialize)]
struct MonitorInfo {
    workspaces: Vec<WorkspaceInfo>,
}

#[derive(Serialize)]
struct WorkspaceInfo {
    id: i32,
    name: String,
    active: bool,
    toplevels: Vec<ToplevelInfo>,
}

#[derive(Serialize)]
struct ToplevelInfo {
    app_id: Option<String>,
    icon_name: Option<String>,
}

#[derive(Serialize)]
struct ActiveWindowInfo {
    title: String,
    app_id: Option<String>,
    icon_name: Option<String>,
}

fn get_system_data_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();

    if let Ok(home) = env::var("HOME") {
        dirs.push(PathBuf::from(home).join(".local/share"));
    }

    let xdg_data_dirs = env::var("XDG_DATA_DIRS")
        .unwrap_or_else(|_| "/usr/local/share:/usr/share".to_string());

    dirs.extend(
        xdg_data_dirs
            .split(':')
            .filter(|s| !s.is_empty())
            .map(PathBuf::from),
    );

    dirs
}

fn get_file_by_suffix(directory: &Path, suffix: &str, check_lower_case: bool) -> Option<PathBuf> {
    if !directory.exists() {
        return None;
    }

    for entry in WalkDir::new(directory)
        .follow_links(true)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|e| {
            let ft = e.file_type();
            if ft.is_file() {
                true
            } else if ft.is_symlink() {
                fs::metadata(e.path()).map(|m| m.is_file()).unwrap_or(false)
            } else {
                false
            }
        })
    {
        let filename = entry.file_name().to_string_lossy();

        if filename.len() < suffix.len() {
            continue;
        }

        if filename.ends_with(suffix) {
            return Some(entry.path().to_path_buf());
        }

        if check_lower_case {
            let suffix_lower = suffix.to_lowercase();
            if filename.ends_with(&suffix_lower) {
                return Some(entry.path().to_path_buf());
            }
        }
    }

    None
}

fn get_desktop_file_path(
    app_identifier: &str,
    alternative_app_identifier: &str,
) -> Option<PathBuf> {
    if app_identifier.is_empty() {
        return None;
    }

    let data_dirs = get_system_data_dirs();

    for data_dir in data_dirs {
        let data_app_dir = data_dir.join("applications");

        let desktop_file_suffix = format!("{}.desktop", app_identifier);
        if let Some(path) = get_file_by_suffix(&data_app_dir, &desktop_file_suffix, true) {
            return Some(path);
        }

        if !alternative_app_identifier.is_empty() {
            let desktop_file_suffix = format!("{}.desktop", alternative_app_identifier);
            if let Some(path) = get_file_by_suffix(&data_app_dir, &desktop_file_suffix, true) {
                return Some(path);
            }
        }
    }

    None
}

fn has_icon_in_theme(icon_name: &str) -> bool {
    let mut icon_dirs = vec![
        PathBuf::from("/usr/share/icons/hicolor"),
        PathBuf::from("/usr/share/pixmaps"),
    ];

    if let Ok(home) = env::var("HOME") {
        icon_dirs.push(PathBuf::from(home).join(".local/share/icons"));
    }

    for data_dir in get_system_data_dirs() {
        icon_dirs.push(data_dir.join("icons/hicolor"));
        icon_dirs.push(data_dir.join("pixmaps"));
    }

    for icon_dir in icon_dirs {
        if !icon_dir.exists() {
            continue;
        }

        for ext in &[".png", ".svg", ".xpm"] {
            let pattern = format!("{}{}", icon_name, ext);

            for entry in WalkDir::new(&icon_dir)
                .follow_links(true)
                .into_iter()
                .filter_map(Result::ok)
                .filter(|e| {
                    let ft = e.file_type();
                    if ft.is_file() {
                        true
                    } else if ft.is_symlink() {
                        fs::metadata(e.path()).map(|m| m.is_file()).unwrap_or(false)
                    } else {
                        false
                    }
                })
            {
                if entry.file_name().to_string_lossy() == pattern {
                    return true;
                }
            }
        }
    }

    false
}

fn read_desktop_file_icon(desktop_file_path: &Path) -> Option<String> {
    let content = fs::read_to_string(desktop_file_path).ok()?;
    let mut in_desktop_entry = false;

    for line in content.lines() {
        let line = line.trim();

        if line == "[Desktop Entry]" {
            in_desktop_entry = true;
            continue;
        }

        if line.starts_with('[') && line.ends_with(']') {
            in_desktop_entry = false;
            continue;
        }

        if in_desktop_entry && line.starts_with("Icon=") {
            return Some(line.strip_prefix("Icon=")?.trim().to_string());
        }
    }

    None
}

fn get_icon_name(app_identifier: &str, alternative_app_identifier: &str) -> Option<String> {
    if let Some(desktop_file_path) = get_desktop_file_path(app_identifier, alternative_app_identifier)
    {
        if let Some(icon_name) = read_desktop_file_icon(&desktop_file_path) {
            return Some(icon_name);
        }
    }

    if has_icon_in_theme(app_identifier) {
        return Some(app_identifier.to_string());
    }

    let app_identifier_lower = app_identifier.to_lowercase();
    if app_identifier_lower != app_identifier && has_icon_in_theme(&app_identifier_lower) {
        return Some(app_identifier_lower);
    }

    let app_identifier_desktop = format!("{}-desktop", app_identifier);
    if has_icon_in_theme(&app_identifier_desktop) {
        return Some(app_identifier_desktop);
    }

    if let Some(first_space_idx) = app_identifier.find(' ') {
        let first_word = app_identifier[..first_space_idx].to_lowercase();
        if has_icon_in_theme(&first_word) {
            return Some(first_word);
        }
    }

    if let Some(first_dash_idx) = app_identifier.find('-') {
        let first_word = app_identifier[..first_dash_idx].to_lowercase();
        if has_icon_in_theme(&first_word) {
            return Some(first_word);
        }
    }

    None
}



fn get_workspace_state(cache: &IconCache) -> WorkspaceState {
    let workspaces = match hyprland::data::Workspaces::get() {
        Ok(ws) => ws,
        Err(_) => return WorkspaceState {
            monitors: HashMap::new(),
            active_window: None,
        },
    };

    let clients = match hyprland::data::Clients::get() {
        Ok(cs) => cs,
        Err(_) => return WorkspaceState {
            monitors: HashMap::new(),
            active_window: None,
        },
    };

    let monitors = match hyprland::data::Monitors::get() {
        Ok(ms) => ms,
        Err(_) => return WorkspaceState {
            monitors: HashMap::new(),
            active_window: None,
        },
    };

    // Build monitor ID to name mapping and active workspace per monitor
    let monitor_map: HashMap<i128, String> = monitors
        .iter()
        .map(|m| (m.id, m.name.clone()))
        .collect();

    let active_workspace_per_monitor: HashMap<i128, i32> = monitors
        .iter()
        .map(|m| (m.id, m.active_workspace.id))
        .collect();

    let active_window = hyprland::data::Client::get_active();

    // Group workspaces by monitor
    let mut monitors_map: HashMap<String, Vec<WorkspaceInfo>> = HashMap::new();

    for workspace in workspaces.iter() {
        let workspace_clients: Vec<ToplevelInfo> = clients
            .iter()
            .filter(|c| c.workspace.id == workspace.id)
            .map(|c| {
                let app_id = if c.class.is_empty() {
                    None
                } else {
                    Some(c.class.clone())
                };
                let key = (c.class.clone(), c.initial_class.clone());
                let icon_name = if let Some(cached) = cache.borrow_mut().get(&key).cloned() {
                    cached
                } else {
                    let icon = get_icon_name(&c.class, &c.initial_class);
                    cache.borrow_mut().put(key, icon.clone());
                    icon
                };
                ToplevelInfo { app_id, icon_name }
            })
            .collect();

        let monitor_name = workspace.monitor_id
            .and_then(|id| monitor_map.get(&id))
            .cloned()
            .unwrap_or_else(|| "unknown".to_string());

        let is_active = workspace.monitor_id
            .and_then(|id| active_workspace_per_monitor.get(&id))
            .map(|active_id| *active_id == workspace.id)
            .unwrap_or(false);

        let workspace_info = WorkspaceInfo {
            id: workspace.id,
            name: workspace.name.clone(),
            active: is_active,
            toplevels: workspace_clients,
        };

        monitors_map.entry(monitor_name)
            .or_insert_with(Vec::new)
            .push(workspace_info);
    }

    // Convert to final structure and sort workspaces by ID
    let monitors_output: HashMap<String, MonitorInfo> = monitors_map
        .into_iter()
        .map(|(name, mut workspaces)| {
            workspaces.sort_by_key(|w| w.id);
            (name, MonitorInfo { workspaces })
        })
        .collect();

    let active_window_info = match active_window {
        Ok(Some(win)) => {
            let app_id = if win.class.is_empty() {
                None
            } else {
                Some(win.class.clone())
            };
            let key = (win.class.clone(), win.initial_class.clone());
            let icon_name = if let Some(cached) = cache.borrow_mut().get(&key).cloned() {
                cached
            } else {
                let icon = get_icon_name(&win.class, &win.initial_class);
                cache.borrow_mut().put(key, icon.clone());
                icon
            };
            Some(ActiveWindowInfo {
                title: win.title,
                app_id,
                icon_name,
            })
        }
        _ => None,
    };

    WorkspaceState {
        monitors: monitors_output,
        active_window: active_window_info,
    }
}

fn emit_workspace_state(cache: &IconCache) {
    let state = get_workspace_state(cache);
    match serde_json::to_string(&state) {
        Ok(json) => println!("{}", json),
        Err(e) => eprintln!("Error serializing workspace state: {}", e),
    }
}

fn main() {
    let args = Args::parse();
    let cache: IconCache = Rc::new(RefCell::new(LruCache::new(
        NonZeroUsize::new(128).unwrap(),
    )));

    // Emit initial workspace state
    emit_workspace_state(&cache);

    if args.monitor {
        // Set up event listener for continuous monitoring
        let mut event_listener = EventListener::new();

        let cache_clone = cache.clone();
        event_listener.add_window_opened_handler(move |_| emit_workspace_state(&cache_clone));

        let cache_clone = cache.clone();
        event_listener.add_window_closed_handler(move |_| emit_workspace_state(&cache_clone));

        let cache_clone = cache.clone();
        event_listener.add_window_moved_handler(move |_| emit_workspace_state(&cache_clone));

        let cache_clone = cache.clone();
        event_listener.add_active_window_changed_handler(move |_| emit_workspace_state(&cache_clone));

        let cache_clone = cache.clone();
        event_listener.add_workspace_added_handler(move |_| emit_workspace_state(&cache_clone));

        let cache_clone = cache.clone();
        event_listener.add_workspace_deleted_handler(move |_| emit_workspace_state(&cache_clone));

        let cache_clone = cache.clone();
        event_listener.add_workspace_moved_handler(move |_| emit_workspace_state(&cache_clone));

        let cache_clone = cache.clone();
        event_listener.add_workspace_renamed_handler(move |_| emit_workspace_state(&cache_clone));

        let cache_clone = cache.clone();
        event_listener.add_active_monitor_changed_handler(move |_| emit_workspace_state(&cache_clone));

        if let Err(e) = event_listener.start_listener() {
            eprintln!("Error starting event listener: {}", e);
            std::process::exit(1);
        }
    }
    // Otherwise just exit after emitting once
}
