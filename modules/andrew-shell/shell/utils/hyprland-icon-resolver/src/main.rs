use clap::Parser;
use hyprland::event_listener::EventListener;
use hyprland::shared::HyprData;
use lru::LruCache;
use std::cell::RefCell;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::num::NonZeroUsize;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use walkdir::WalkDir;

#[derive(Parser)]
#[command(name = "hyprland-icon-resolve")]
#[command(about = "Resolve Hyprland window icons")]
struct Args {
    #[arg(long, help = "Watch for window changes and emit JSON on updates")]
    watch: bool,
}

type IconCache = Rc<RefCell<LruCache<(String, String), Option<String>>>>;

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



fn get_all_icons(cache: &IconCache) -> HashMap<String, Option<String>> {
    let clients = match hyprland::data::Clients::get() {
        Ok(clients) => clients,
        Err(e) => {
            eprintln!("Error getting clients: {}", e);
            return HashMap::new();
        }
    };

    let mut unique_classes: HashMap<String, String> = HashMap::new();
    
    for client in clients {
        unique_classes.entry(client.class.clone()).or_insert(client.initial_class);
    }

    let mut result: HashMap<String, Option<String>> = HashMap::new();

    for (class, initial_class) in unique_classes {
        let key = (class.clone(), initial_class.clone());
        let icon_name = if let Some(cached) = cache.borrow_mut().get(&key).cloned() {
            cached
        } else {
            let icon = get_icon_name(&class, &initial_class);
            cache.borrow_mut().put(key, icon.clone());
            icon
        };
        result.insert(class, icon_name);
    }

    result
}

fn emit_json(cache: &IconCache) {
    let result = get_all_icons(cache);
    match serde_json::to_string(&result) {
        Ok(json) => println!("{}", json),
        Err(e) => eprintln!("Error serializing JSON: {}", e),
    }
}

fn main() {
    let args = Args::parse();
    let cache: IconCache = Rc::new(
        RefCell::new(
            LruCache::new(
                NonZeroUsize::new(128).unwrap()
            )
        )
    );

    if args.watch {
        // Emit initial state
        emit_json(&cache);

        // Set up event listener
        let mut event_listener = EventListener::new();

        let cache_clone = cache.clone();
        event_listener.add_window_opened_handler(move |_| emit_json(&cache_clone));
        
        let cache_clone = cache.clone();
        event_listener.add_window_closed_handler(move |_| emit_json(&cache_clone));

        if let Err(e) = event_listener.start_listener() {
            eprintln!("Error starting event listener: {}", e);
            std::process::exit(1);
        }
    } else {
        // One-shot mode
        let result = get_all_icons(&cache);
        match serde_json::to_string(&result) {
            Ok(json) => println!("{}", json),
            Err(e) => {
                eprintln!("Error serializing JSON: {}", e);
                std::process::exit(1);
            }
        }
    }
}
