# Hyprland Info

A utility to provide workspace and window information for Hyprland, including icon resolution for application windows.

## Usage

```bash
# One-shot mode: emit current workspace and window state as JSON, then exit
hyprland-info

# Monitor mode: continuously watch and emit JSON on every change
hyprland-info --monitor
```

The tool outputs JSON containing:
- Workspace information grouped by monitor
- Active workspace per monitor
- Window titles and application IDs
- Resolved icon names for each window

## Icon Resolution Algorithm

> **Note:** The resolution algorithm is borrowed mostly from [Waybar](https://github.com/Alexays/Waybar).

The resolver attempts to find the appropriate icon for each window using a multi-step fallback strategy:

### 1. Desktop File Lookup

First, the resolver searches for a `.desktop` file matching the window's class or initial class:

- Searches in XDG data directories (`~/.local/share/applications`, `/usr/share/applications`, etc.)
- Tries both the window `class` and `initial_class` identifiers
- Case-insensitive matching (supports both `Firefox.desktop` and `firefox.desktop`)
- If found, extracts the `Icon=` value from the `[Desktop Entry]` section

### 2. Direct Icon Theme Lookup

If no desktop file is found or it doesn't contain an icon, the resolver searches icon themes directly:

**Step 2a:** Search for the exact app identifier
- Checks icon directories for files matching `{app_identifier}.{png,svg,xpm}`

**Step 2b:** Try lowercase variant
- If the app identifier contains uppercase letters, tries the lowercase version
- Example: `"Firefox"` → searches for `"firefox"`

**Step 2c:** Try with `-desktop` suffix
- Checks for `{app_identifier}-desktop.{png,svg,xpm}`

**Step 2d:** Try first word before space
- If the app identifier contains spaces, extracts the first word (lowercased)
- Example: `"Google Chrome"` → searches for `"google"`

**Step 2e:** Try first segment before dash
- If the app identifier contains dashes, extracts the first segment (lowercased)
- Example: `"org-gnome-terminal"` → searches for `"org"`

### Icon Search Locations

The resolver recursively searches the following directories and all subdirectories:
- User directories:
  - `~/.local/share/icons`
- System directories (from XDG_DATA_DIRS):
  - `{data_dir}/icons/hicolor`
  - `{data_dir}/pixmaps`

Supported icon formats: `.png`, `.svg`, `.xpm`

### Caching

Results are cached using an LRU cache (128 entries) with `(class, initial_class)` as the key to avoid redundant filesystem lookups.

## Output Format

The tool outputs JSON mapping window classes to their resolved icon names:

```json
{
  "firefox": "firefox",
  "org.gnome.Nautilus": "org.gnome.Nautilus",
  "Alacritty": "Alacritty",
  "unknown-app": null
}
```

Windows without resolved icons map to `null`.
