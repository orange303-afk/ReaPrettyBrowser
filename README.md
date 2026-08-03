# ReaPrettyBrowser - Visual Plugin Browser for REAPER

**ReaPrettyBrowser** is a modern, visual **FX Plugin Browser** script for **Cockos REAPER** built with **ReaImGui**. It automatically scans REAPER's plugin database, imports VST/AU/CLAP snapshots/thumbnails, supports category submenus, drag-and-drop to tracks, instrument slot-0 positioning, clipboard thumbnail pasting, targeted plugin GUI screenshots, settings backup/restore, and full cross-platform support for **macOS & Windows**.

![Uploading image.png…]()

---

## Features

- **Responsive Single-Column Grid**: Auto-scaling cards that fill 100% of docker width as you resize REAPER panels.
- **Multi-Category Assignment Submenu**: Assign multiple categories to plugins with instant `✓` checkboxes and 1-click toggling.
- **Targeted Plugin GUI Screenshot**: Right-click -> `Screenshot open plugin GUI...` captures ONLY the plugin interface window without REAPER background.
- **Paste Clipboard Thumbnail**: Right-click -> `Paste thumbnail from clipboard` converts any copied image into a plugin card preview.
- **Smart Instrument Placement**: Instrument VSTis are automatically instantiated in Slot 0 (first insert slot) on selected or newly created MIDI tracks.
- **Custom Folder Browser & Settings Backup**: Browse for snapshot folders, and export/import all browser settings via `Settings...`.
- **Lazy Texture Loading & Caching**: Efficient texture rendering prevents freeze or lag on large plugin collections.
- **Real-time Search & Filters**: Search by plugin name, vendor, or format instantly (`All`, `Favorites`, `VST3`, `VST`, `AU`, `CLAP`).
- **Drag & Drop to Tracks**: Drag single or multiple selected plugins directly onto tracks or empty arrange space to create pre-configured tracks.
- **Cross-Platform**: 100% native support for **macOS & Windows**.

---

## Requirements

- **Cockos REAPER** v6.0 or higher.
- **ReaImGui extension** (Install via ReaPack: `Extensions -> ReaPack -> Browse packages -> search 'ReaImGui'`).

---

## Installation & Setup

1. **Unzip Archive**:
   Extract `ReaPrettyBrowser_v1.0.zip`.

2. **Copy Included Snapshots (Optional)**:
   Copy the contents of the included `Thumbnails/` folder to:
   - **macOS**: `~/Documents/Reaper/Thumbnails`
   - **Windows**: `%USERPROFILE%\Documents\Reaper\Thumbnails`

3. **Load Script in REAPER**:
   - Open REAPER.
   - Open Action List (`Actions -> Show action list...` or `?`).
   - Click `New action... -> Load ReaScript...`.
   - Select `ReaPrettyBrowser.lua`.
   - Run the script!

---

## Included Package Structure

- [`ReaPrettyBrowser.lua`](file:///Users/ilyaorange/Documents/ReaPrettyBrowser/ReaPrettyBrowser.lua): Main script & ReaImGui event loop.
- `Thumbnails/`: 794 pre-made high-resolution plugin GUI snapshots.
- `modules/`:
  - `plugin_scanner.lua`: REAPER INI database parser & snapshot scanner.
  - `ui_views.lua`: Main responsive UI layout, context submenus, and dialogs.
  - `ui_theme.lua`: HSL dark palette & format badge colors.
  - `texture_manager.lua`: Lazy texture loader & LRU cache.
  - `config.lua`: ExtState storage, category management, export & import settings.
  - `capture_plugin_gui.py`: Win32 / macOS window rectangle screenshot engine.
  - `save_clipboard_image.py`: Win32 / macOS clipboard image extractor.
  - `download_google_thumbnail.py`: Automatic web/Google image search & thumbnail retriever.

---

## Created By

**Ilya Orange**
- Website: [ilyaorange.gumroad.com](https://ilyaorange.gumroad.com)
- Bandcamp: [ilyaorange.bandcamp.com](https://ilyaorange.bandcamp.com)
- Project: [naukograd.bandcamp.com](https://naukograd.bandcamp.com)
- Support: [paypal.me/ilyaorange303](https://paypal.com/paypalme/ilyaorange303)
