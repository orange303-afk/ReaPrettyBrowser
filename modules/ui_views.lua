-- Module: modules/ui_views.lua
-- Main UI layout, search, filters, category/vendor combos, single-column responsive grid layout, multi-selection, drag & drop, context menus, custom categories, backups, and About modal.

local UIViews = {}

local UITheme = require("modules.ui_theme")
local Config = require("modules.config")
local TextureManager = require("modules.texture_manager")

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- Open URL in OS default web browser
local function open_url(url)
  if not url or url == "" then return end
  local os_name = reaper.GetOS()
  if os_name:sub(1, 3) == "Win" then
    os.execute('start "" "' .. url .. '"')
  else
    os.execute('open "' .. url .. '"')
  end
end

-- Native Folder Picker Dialog
local function browse_for_custom_folder(state)
  local os_name = reaper.GetOS()
  local folder = ""

  if reaper.APIExists("JS_Dialog_BrowseForFolder") then
    local retval, user_folder = reaper.JS_Dialog_BrowseForFolder("Select Custom Snapshots Folder", state.custom_snapshot_path or "")
    if retval == 1 and user_folder and user_folder ~= "" then
      folder = user_folder
    end
  elseif os_name:sub(1, 3) == "Win" then
    local ps_script = [[
      Add-Type -AssemblyName System.Windows.Forms
      $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
      if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-Output $dialog.SelectedPath
      }
    ]]
    local handle = io.popen('powershell -NoProfile -ExecutionPolicy Bypass -Command "' .. ps_script:gsub('"', '\"') .. '"')
    if handle then
      folder = handle:read("*a") or ""
      handle:close()
    end
  else
    local cmd = '/usr/bin/osascript -e \'POSIX path of (choose folder with prompt "Select Custom Snapshots Directory")\''
    local handle = io.popen(cmd)
    if handle then
      folder = handle:read("*a") or ""
      handle:close()
    end
  end

  folder = folder:match("^%s*(.-)%s*$")
  if folder ~= "" then
    state.custom_snapshot_path = folder
    Config.save_custom_snapshot_path(folder)
  end
end

-- Backup / Export all ExtState settings to a user specified file
local function export_settings_dialog(state)
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  local dest = home .. "/Documents/ReaPrettyBrowser_Backup.txt"
  
  local os_name = reaper.GetOS()
  if os_name:sub(1, 3) == "Win" then
    local ps_script = [[
      Add-Type -AssemblyName System.Windows.Forms
      $dialog = New-Object System.Windows.Forms.SaveFileDialog
      $dialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
      $dialog.FileName = "ReaPrettyBrowser_Backup.txt"
      if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-Output $dialog.FileName
      }
    ]]
    local handle = io.popen('powershell -NoProfile -ExecutionPolicy Bypass -Command "' .. ps_script:gsub('"', '\"') .. '"')
    if handle then
      local picked = handle:read("*a") or ""
      handle:close()
      picked = picked:match("^%s*(.-)%s*$")
      if picked ~= "" then dest = picked end
    end
  else
    local cmd = '/usr/bin/osascript -e \'POSIX path of (choose file name with prompt "Export All Settings Backup" default name "ReaPrettyBrowser_Backup.txt")\''
    local handle = io.popen(cmd)
    if handle then
      local picked = handle:read("*a") or ""
      handle:close()
      picked = picked:match("^%s*(.-)%s*$")
      if picked ~= "" then dest = picked end
    end
  end

  if Config.export_all_settings(dest) then
    state.status_message = "✅ Settings exported to: " .. dest
  end
end

-- Import / Restore all ExtState settings from a user specified backup file
local function import_settings_dialog(state)
  local os_name = reaper.GetOS()
  local src = ""

  if os_name:sub(1, 3) == "Win" then
    local ps_script = [[
      Add-Type -AssemblyName System.Windows.Forms
      $dialog = New-Object System.Windows.Forms.OpenFileDialog
      $dialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
      if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-Output $dialog.FileName
      }
    ]]
    local handle = io.popen('powershell -NoProfile -ExecutionPolicy Bypass -Command "' .. ps_script:gsub('"', '\"') .. '"')
    if handle then
      src = handle:read("*a") or ""
      handle:close()
    end
  else
    local cmd = '/usr/bin/osascript -e \'POSIX path of (choose file with prompt "Select ReaPrettyBrowser Backup File")\''
    local handle = io.popen(cmd)
    if handle then
      src = handle:read("*a") or ""
      handle:close()
    end
  end

  src = src:match("^%s*(.-)%s*$")
  if src ~= "" and Config.import_all_settings(src) then
    local PluginScanner = require("modules.plugin_scanner")
    state.plugins, state.snapshot_dirs, state.vendor_list = PluginScanner.scan_all_plugins(state.custom_snapshot_path)
    state.favorites = Config.get_favorites()
    TextureManager.reset()
    state.status_message = "✅ Settings restored from: " .. src
  end
end

-- Helper to get full list of available categories (Standard + User Created)
local function get_all_category_options(include_all_option)
  local list = {}
  if include_all_option then
    table.insert(list, "All Categories")
  end
  local std = {
    "Instruments", "Compressors", "EQ & Filters",
    "Reverbs", "Delays", "Modulation", "Distortion", "Pitch & Vocal", "Utilities"
  }
  for _, s in ipairs(std) do
    table.insert(list, s)
  end

  local user_cats = Config.get_user_category_list()
  for _, u_cat in ipairs(user_cats) do
    local exists = false
    for _, item in ipairs(list) do
      if item:lower() == u_cat:lower() then exists = true break end
    end
    if not exists then table.insert(list, u_cat) end
  end

  return list
end

-- Capture screenshot of ONLY open plugin window interface
local function capture_plugin_screenshot(plugin, state)
  if not plugin then return end

  -- Float plugin window if open on selected track
  local track = reaper.GetSelectedTrack(0, 0)
  if track then
    local fx_count = reaper.TrackFX_GetCount(track)
    for k = 0, fx_count - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(track, k, "")
      if fx_name:lower():find(plugin.name:lower(), 1, true) then
        reaper.TrackFX_Show(track, k, 3)
        break
      end
    end
  end

  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  local thumb_dir = home .. "/Documents/Reaper/Thumbnails"
  
  local safe_vendor = (plugin.vendor or "Unknown"):gsub("[%s%p]", "_")
  local safe_name = (plugin.name or "Plugin"):gsub("[%s%p]", "_")
  local dest_path = thumb_dir .. "/" .. safe_vendor .. "_" .. safe_name .. ".png"

  local script_py = "/Users/ilyaorange/Documents/ReaPrettyBrowser/modules/capture_plugin_gui.py"
  local cmd = string.format('python3 "%s" "%s"', script_py, dest_path)

  local handle = io.popen(cmd)
  local result = handle and handle:read("*a") or ""
  if handle then handle:close() end

  result = result:match("^%s*(.-)%s*$")

  if result == "SUCCESS" and file_exists(dest_path) then
    Config.save_custom_thumbnail(plugin.ident, dest_path)
    if plugin.uid then Config.save_custom_thumbnail(plugin.uid, dest_path) end
    if plugin.full_name then Config.save_custom_thumbnail(plugin.full_name, dest_path) end
    
    plugin.snapshot_path = dest_path
    
    if state and state.plugins then
      for _, item in ipairs(state.plugins) do
        if item.ident == plugin.ident or item.uid == plugin.uid or item.full_name == plugin.full_name then
          item.snapshot_path = dest_path
        end
      end
    end

    TextureManager.reset()
  end
end

-- Save image from OS Clipboard to plugin snapshot
local function paste_thumbnail_from_clipboard(plugin, state)
  if not plugin then return end

  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  local thumb_dir = home .. "/Documents/Reaper/Thumbnails"
  
  local safe_vendor = (plugin.vendor or "Unknown"):gsub("[%s%p]", "_")
  local safe_name = (plugin.name or "Plugin"):gsub("[%s%p]", "_")
  local dest_path = thumb_dir .. "/" .. safe_vendor .. "_" .. safe_name .. ".png"

  local os_name = reaper.GetOS()
  local result = "NO_IMAGE"

  if os_name:sub(1, 3) == "Win" then
    local ps_script = string.format([[
      Add-Type -AssemblyName System.Windows.Forms
      $img = [System.Windows.Forms.Clipboard]::GetImage()
      if ($img -ne $null) {
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName('%s'))
        $img.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output "SUCCESS"
      } else { Write-Output "NO_IMAGE" }
    ]], dest_path:gsub("/", "\\"), dest_path:gsub("/", "\\"))

    local cmd = string.format('powershell -NoProfile -ExecutionPolicy Bypass -Command "%s"', ps_script:gsub('"', '\"'))
    local handle = io.popen(cmd)
    if handle then
      result = handle:read("*a") or ""
      handle:close()
    end
  else
    -- macOS 100% native AppleScript
    local applescript_path = reaper.GetResourcePath() .. "/Scripts/ReaPrettyBrowser_paste_clip.applescript"
    if not file_exists(applescript_path) then
      applescript_path = "/Users/ilyaorange/Documents/ReaPrettyBrowser/modules/get_clipboard_mac.applescript"
    end

    local cmd = string.format('/usr/bin/osascript "%s" "%s"', applescript_path, dest_path)
    local handle = io.popen(cmd)
    if handle then
      result = handle:read("*a") or ""
      handle:close()
    end
  end

  result = result:match("^%s*(.-)%s*$")

  if (result == "SUCCESS" or file_exists(dest_path)) and file_exists(dest_path) then
    Config.save_custom_thumbnail(plugin.ident, dest_path)
    if plugin.uid then Config.save_custom_thumbnail(plugin.uid, dest_path) end
    if plugin.full_name then Config.save_custom_thumbnail(plugin.full_name, dest_path) end
    
    plugin.snapshot_path = dest_path
    
    if state and state.plugins then
      for _, item in ipairs(state.plugins) do
        if item.ident == plugin.ident or item.uid == plugin.uid or item.full_name == plugin.full_name then
          item.snapshot_path = dest_path
        end
      end
    end

    TextureManager.reset()
  else
    state.clipboard_error_plugin = plugin
    state.trigger_open_no_clipboard_img_popup = true
  end
end

-- Helper to insert FX on a specific REAPER track
local function insert_plugin_to_track(track, plugin)
  if not track or not plugin then return false end

  reaper.Undo_BeginBlock()

  local candidates = {
    plugin.ident,
    plugin.raw_key,
    plugin.full_name,
    plugin.type and (plugin.type .. ": " .. (plugin.raw_key or "")) or nil,
    plugin.type and (plugin.type .. ": " .. (plugin.full_name or "")) or nil,
    plugin.name,
  }

  -- Instrument plugins always target Slot 0 (-1000 = first FX insert slot)
  local is_instrument = (plugin.category == "Instruments") or 
                        (plugin.type == "VSTi") or 
                        (plugin.full_name and plugin.full_name:find("!!!VSTi"))

  local instantiate_slot = is_instrument and -1000 or -1

  local fx_index = -1
  for _, cand in ipairs(candidates) do
    if cand and cand ~= "" then
      fx_index = reaper.TrackFX_AddByName(track, cand, false, instantiate_slot)
      if fx_index >= 0 then break end
    end
  end

  if fx_index >= 0 then
    reaper.TrackFX_Show(track, fx_index, 3)
    reaper.Undo_EndBlock("ReaPrettyBrowser: Add " .. plugin.name, -1)
    return true
  end

  reaper.Undo_EndBlock("ReaPrettyBrowser: Add FX Failed", -1)
  return false
end

-- Create a new REAPER track configured with MIDI: ALL Input, Record: output (stereo), & Stereo Output
local function create_configured_track()
  local track_idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(track_idx, true)
  local track = reaper.GetTrack(0, track_idx)

  if track then
    reaper.SetOnlyTrackSelected(track)
    reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", 6112)
    reaper.SetMediaTrackInfo_Value(track, "I_RECMODE", 1)
    reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
    reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
    reaper.SetMediaTrackInfo_Value(track, "I_NCHAN", 2)
    reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 1)
  end

  return track
end

-- Helper to get ordered list of selected plugins
local function get_selected_plugin_list(state, filtered)
  local list = {}
  local set = state.selected_plugins or {}

  if filtered then
    for _, p in ipairs(filtered) do
      local p_key = p.uid or p.ident
      if set[p_key] then
        table.insert(list, p)
      end
    end
  end

  if #list == 0 then
    local target = state.context_plugin or state.assign_group_plugin or state.selected_plugin
    if target then
      table.insert(list, target)
    end
  end

  return list
end

local function insert_selected_plugins(state, filtered, target_track)
  local list = get_selected_plugin_list(state, filtered)
  if #list == 0 then return end

  local track = target_track or reaper.GetSelectedTrack(0, 0)
  if not track then
    track = create_configured_track()
  end

  for _, p in ipairs(list) do
    insert_plugin_to_track(track, p)
  end
end

-- Open folder in OS File Explorer / Finder
local function open_in_explorer(folder_path)
  if not folder_path or folder_path == "" then return end
  local os_name = reaper.GetOS()
  if os_name:sub(1, 3) == "Win" then
    os.execute('explorer "' .. folder_path:gsub("/", "\\") .. '"')
  else
    os.execute('open "' .. folder_path .. '"')
  end
end

function UIViews.draw_toolbar(ctx, state)
  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  local is_narrow = avail_w < 560
  local cat_options = get_all_category_options(true)

  if is_narrow then
    -- Responsive Vertical Layout for Narrow Docker Panel
    -- 1. Search Bar (Full width)
    reaper.ImGui_PushItemWidth(ctx, -1)
    local changed, search_txt = reaper.ImGui_InputTextWithHint(ctx, "##SearchPlugins", "🔍 Search plugins...", state.search_query)
    if changed then
      state.search_query = search_txt
      Config.save_filters(state)
    end
    state.is_search_active = reaper.ImGui_IsItemActive(ctx)
    reaper.ImGui_PopItemWidth(ctx)

    -- 2. Category & Vendor Dropdowns (2 columns at 50% width)
    local half_w = math.max(90, (avail_w - 6) * 0.5)
    reaper.ImGui_PushItemWidth(ctx, half_w)
    if reaper.ImGui_BeginCombo(ctx, "##CategoryCombo", state.selected_category or "All Categories") then
      for _, cat in ipairs(cat_options) do
        local is_selected = (state.selected_category == cat)
        if reaper.ImGui_Selectable(ctx, cat, is_selected) then
          state.selected_category = cat
          Config.save_filters(state)
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_PopItemWidth(ctx)

    reaper.ImGui_SameLine(ctx, 0, 6)

    reaper.ImGui_PushItemWidth(ctx, half_w)
    if reaper.ImGui_BeginCombo(ctx, "##VendorCombo", state.selected_vendor or "All Vendors") then
      if state.vendor_list then
        for _, v in ipairs(state.vendor_list) do
          local is_selected = (state.selected_vendor == v)
          if reaper.ImGui_Selectable(ctx, v, is_selected) then
            state.selected_vendor = v
            Config.save_filters(state)
          end
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_PopItemWidth(ctx)

    -- 3. Format Tabs & Snapshots / About Buttons
    local categories = { "All", "Fav", "VST3", "VST", "AU", "CLAP" }
    for _, cat in ipairs(categories) do
      local target_cat = (cat == "Fav" and "Favorites" or cat)
      local is_active = (state.active_category == target_cat)
      if is_active then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), UITheme.COLORS.HeaderActive)
      end
      
      if reaper.ImGui_Button(ctx, cat) then
        state.active_category = target_cat
        Config.save_filters(state)
      end

      if is_active then
        reaper.ImGui_PopStyleColor(ctx)
      end
      reaper.ImGui_SameLine(ctx)
    end

    if reaper.ImGui_Button(ctx, "⚙️ Settings...") then
      reaper.ImGui_OpenPopup(ctx, "SettingsPopup")
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "ℹ️ About") then
      reaper.ImGui_OpenPopup(ctx, "AboutPopup")
    end

  else
    -- Wide Horizontal Layout
    reaper.ImGui_PushItemWidth(ctx, 180)
    local changed, search_txt = reaper.ImGui_InputTextWithHint(ctx, "##SearchPlugins", "🔍 Search plugins...", state.search_query)
    if changed then
      state.search_query = search_txt
      Config.save_filters(state)
    end
    state.is_search_active = reaper.ImGui_IsItemActive(ctx)
    reaper.ImGui_PopItemWidth(ctx)

    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_PushItemWidth(ctx, 130)
    if reaper.ImGui_BeginCombo(ctx, "##CategoryCombo", state.selected_category or "All Categories") then
      for _, cat in ipairs(cat_options) do
        local is_selected = (state.selected_category == cat)
        if reaper.ImGui_Selectable(ctx, cat, is_selected) then
          state.selected_category = cat
          Config.save_filters(state)
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_PopItemWidth(ctx)

    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_PushItemWidth(ctx, 130)
    if reaper.ImGui_BeginCombo(ctx, "##VendorCombo", state.selected_vendor or "All Vendors") then
      if state.vendor_list then
        for _, v in ipairs(state.vendor_list) do
          local is_selected = (state.selected_vendor == v)
          if reaper.ImGui_Selectable(ctx, v, is_selected) then
            state.selected_vendor = v
            Config.save_filters(state)
          end
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_PopItemWidth(ctx)

    reaper.ImGui_SameLine(ctx)

    local categories = { "All", "Favorites", "VST3", "VST", "AU", "CLAP" }
    for _, cat in ipairs(categories) do
      local is_active = (state.active_category == cat)
      if is_active then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), UITheme.COLORS.HeaderActive)
      end
      
      if reaper.ImGui_Button(ctx, cat) then
        state.active_category = cat
        Config.save_filters(state)
      end

      if is_active then
        reaper.ImGui_PopStyleColor(ctx)
      end
      reaper.ImGui_SameLine(ctx)
    end

    if reaper.ImGui_Button(ctx, "⚙️ Settings...") then
      reaper.ImGui_OpenPopup(ctx, "SettingsPopup")
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "ℹ️ About") then
      reaper.ImGui_OpenPopup(ctx, "AboutPopup")
    end
  end

  -- Common Settings Popup Modal
  if reaper.ImGui_BeginPopup(ctx, "SettingsPopup") then
    reaper.ImGui_TextColored(ctx, UITheme.COLORS.AccentCyan, "⚙️ ReaPrettyBrowser Settings")
    reaper.ImGui_Separator(ctx)
    
    reaper.ImGui_Text(ctx, "Custom Snapshots Path:")
    reaper.ImGui_PushItemWidth(ctx, 280)
    local path_changed, new_path = reaper.ImGui_InputText(ctx, "##CustomSnapPath", state.custom_snapshot_path or "")
    if path_changed then
      state.custom_snapshot_path = new_path
      Config.save_custom_snapshot_path(new_path)
    end
    reaper.ImGui_PopItemWidth(ctx)

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Browse...") then
      browse_for_custom_folder(state)
    end

    if reaper.ImGui_Button(ctx, "Rescan Snapshots") then
      local PluginScanner = require("modules.plugin_scanner")
      state.plugins, state.snapshot_dirs, state.vendor_list = PluginScanner.scan_all_plugins(state.custom_snapshot_path)
      require("modules.texture_manager").reset()
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "👁️ Unhide All Hidden") then
      Config.unhide_all()
      for _, p in ipairs(state.plugins) do
        p.is_hidden = nil
      end
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextColored(ctx, UITheme.COLORS.AccentCyan, "Backup & Restore All Settings:")
    if reaper.ImGui_Button(ctx, "💾 Export All Settings...") then
      export_settings_dialog(state)
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "📥 Restore Settings...") then
      import_settings_dialog(state)
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextColored(ctx, UITheme.COLORS.TextMuted, "Auto-scanned folders:")
    for _, dir in ipairs(state.snapshot_dirs) do
      reaper.ImGui_BulletText(ctx, dir)
    end

    reaper.ImGui_EndPopup(ctx)
  end

  -- About Popup attached directly under About button
  if reaper.ImGui_BeginPopup(ctx, "AboutPopup") then
    reaper.ImGui_TextColored(ctx, UITheme.COLORS.AccentCyan, "ReaPrettyBrowser by Ilya Orange")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    local links = {
      { label = "🌐 ilyaorange.gumroad.com", url = "https://ilyaorange.gumroad.com" },
      { label = "🎵 ilyaorange.bandcamp.com", url = "https://ilyaorange.bandcamp.com" },
      { label = "🎶 naukograd.bandcamp.com", url = "https://naukograd.bandcamp.com" },
      { label = "☕ support: paypal.com/paypalme/ilyaorange303", url = "https://paypal.com/paypalme/ilyaorange303" },
    }

    for _, item in ipairs(links) do
      if reaper.ImGui_Selectable(ctx, item.label) then
        open_url(item.url)
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Click to open " .. item.url)
      end
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

function UIViews.draw_plugin_grid(ctx, state)
  local child_flags = 0
  if reaper.ImGui_BeginChild(ctx, "PluginGridRegion", 0, -22, child_flags) then
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local padding = 6

    -- Always single column, width auto-scaling with docker width
    local columns = 1
    local card_w = math.max(120, avail_w - 4)
    local card_h = math.min(500, math.max(160, card_w * 0.55))

    -- Filter & Sort plugins list
    local filtered = {}
    local query = state.search_query:lower()

    for _, p in ipairs(state.plugins) do
      local matches_format = true
      if state.active_category == "Favorites" then
        matches_format = state.favorites[p.ident] == true
      elseif state.active_category ~= "All" then
        matches_format = (p.type == state.active_category)
      end

      local matches_category = true
      if state.selected_category and state.selected_category ~= "All Categories" then
        matches_category = (p.categories and p.categories[state.selected_category] == true) or (p.category == state.selected_category)
      end

      local matches_vendor = true
      if state.selected_vendor and state.selected_vendor ~= "All Vendors" then
        matches_vendor = (p.vendor == state.selected_vendor)
      end

      local matches_query = (query == "") or 
        p.name:lower():find(query, 1, true) or 
        p.vendor:lower():find(query, 1, true) or 
        p.category:lower():find(query, 1, true) or
        p.type:lower():find(query, 1, true)

      if not p.is_hidden and matches_format and matches_category and matches_vendor and matches_query then
        table.insert(filtered, p)
      end
    end

    table.sort(filtered, function(a, b)
      if a.vendor ~= b.vendor then
        return a.vendor:lower() < b.vendor:lower()
      end
      return a.name:lower() < b.name:lower()
    end)

    -- Keyboard Shortcuts: Cmd+A (Select All) / Esc (Deselect All)
    if not state.is_search_active and reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_ChildWindows()) then
      local is_cmd_down = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
      
      if is_cmd_down and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_A()) then
        state.selected_plugins = {}
        for _, p in ipairs(filtered) do
          state.selected_plugins[p.uid or p.ident] = true
        end
      elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        state.selected_plugins = {}
      end
    end

    if #filtered == 0 then
      reaper.ImGui_TextColored(ctx, UITheme.COLORS.TextMuted, "No plugins found matching current filter/search criteria.")
    else
      -- Render single-column grid cards
      for i, plugin in ipairs(filtered) do
        local p_key = plugin.uid or plugin.ident
        reaper.ImGui_PushID(ctx, p_key .. "_" .. i)

        -- Begin Card Group
        local card_start_x, card_start_y = reaper.ImGui_GetCursorScreenPos(ctx)
        
        -- Selectable container card
        local is_fav = state.favorites[plugin.ident] == true
        local is_selected = (state.selected_plugins and state.selected_plugins[p_key] == true)

        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), is_selected and UITheme.COLORS.CardBgSelected or UITheme.COLORS.CardBg)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), UITheme.COLORS.CardBgHovered)
        
        reaper.ImGui_Selectable(ctx, "##CardSelect", is_selected, reaper.ImGui_SelectableFlags_AllowDoubleClick(), card_w, card_h)

        if reaper.ImGui_IsItemClicked(ctx, 0) then
          local is_cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
          local is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())

          if not state.selected_plugins then state.selected_plugins = {} end

          if is_cmd then
            state.selected_plugins[p_key] = not state.selected_plugins[p_key]
          elseif is_shift and state.last_clicked_plugin then
            local idx1, idx2 = nil, nil
            for idx, p in ipairs(filtered) do
              if p == state.last_clicked_plugin then idx1 = idx end
              if p == plugin then idx2 = idx end
            end
            if idx1 and idx2 then
              local s_idx, e_idx = math.min(idx1, idx2), math.max(idx1, idx2)
              for k = s_idx, e_idx do
                local item_key = filtered[k].uid or filtered[k].ident
                state.selected_plugins[item_key] = true
              end
            end
          else
            state.selected_plugins = { [p_key] = true }
          end

          state.selected_plugin = plugin
          state.last_clicked_plugin = plugin

          if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
            insert_selected_plugins(state, filtered)
          end
        end

        -- Drag & Drop Source (Multi-plugin support)
        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
          local selected_list = get_selected_plugin_list(state, filtered)
          reaper.ImGui_SetDragDropPayload(ctx, "FX_PLUGIN_PAYLOAD", plugin.ident)
          state.dragging_plugins = selected_list
          state.dragging_plugin = plugin
          
          if #selected_list > 1 then
            reaper.ImGui_Text(ctx, string.format("➕ Dragging %d plugins", #selected_list))
          else
            reaper.ImGui_Text(ctx, "➕ Dragging: " .. plugin.name)
          end
          reaper.ImGui_EndDragDropSource(ctx)
        end

        -- Context Menu
        if reaper.ImGui_BeginPopupContextItem(ctx, "PluginContextMenu") then
          state.context_plugin = plugin
          local selected_list = get_selected_plugin_list(state, filtered)
          local count = #selected_list

          local ins_label = (count > 1) and string.format("➕ Insert %d selected plugins on track", count) or "➕ Insert on selected track"
          if reaper.ImGui_MenuItem(ctx, ins_label) then
            insert_selected_plugins(state, filtered)
          end
          
          local fav_label = (count > 1) and "⭐ Toggle Favorites for selected" or (is_fav and "⭐ Remove from Favorites" or "★ Add to Favorites")
          if reaper.ImGui_MenuItem(ctx, fav_label) then
            for _, p in ipairs(selected_list) do
              state.favorites[p.ident] = not state.favorites[p.ident]
            end
            Config.save_favorites(state.favorites)
          end
          
          reaper.ImGui_Separator(ctx)
          if reaper.ImGui_MenuItem(ctx, "📸 Screenshot open plugin GUI...") then
            capture_plugin_screenshot(plugin, state)
          end

          if reaper.ImGui_MenuItem(ctx, "📋 Paste thumbnail from clipboard") then
            paste_thumbnail_from_clipboard(plugin, state)
          end

          -- Submenu for Add to Category
          local add_cat_label = (count > 1) and string.format("🏷️ Add to Category (%d selected)", count) or "🏷️ Add to Category"
          if reaper.ImGui_BeginMenu(ctx, add_cat_label) then
            local cat_options = get_all_category_options(false)
            for _, grp in ipairs(cat_options) do
              local is_in_cat = (plugin.categories and plugin.categories[grp] == true)
              if reaper.ImGui_MenuItem(ctx, grp, nil, is_in_cat) then
                if is_in_cat then
                  -- Toggle off / remove category if already present
                  for _, p in ipairs(selected_list) do
                    Config.remove_category_from_plugin(p.ident, grp)
                    if p.uid then Config.remove_category_from_plugin(p.uid, grp) end
                    if p.full_name then Config.remove_category_from_plugin(p.full_name, grp) end
                    if p.categories then p.categories[grp] = nil end

                    if state and state.plugins then
                      for _, item in ipairs(state.plugins) do
                        if item.ident == p.ident or item.uid == p.uid or item.full_name == p.full_name then
                          if item.categories then item.categories[grp] = nil end
                          if item.category == grp then
                            local next_cat = nil
                            if item.categories then
                              for c in pairs(item.categories) do next_cat = c break end
                            end
                            item.category = next_cat or "Utilities"
                          end
                        end
                      end
                    end
                  end
                else
                  -- Add category
                  for _, p in ipairs(selected_list) do
                    Config.add_category_to_plugin(p.ident, grp)
                    if p.uid then Config.add_category_to_plugin(p.uid, grp) end
                    if p.full_name then Config.add_category_to_plugin(p.full_name, grp) end
                    
                    if not p.categories then p.categories = {} end
                    p.categories[grp] = true
                    p.category = grp

                    if state and state.plugins then
                      for _, item in ipairs(state.plugins) do
                        if item.ident == p.ident or item.uid == p.uid or item.full_name == p.full_name then
                          if not item.categories then item.categories = {} end
                          item.categories[grp] = true
                          item.category = grp
                        end
                      end
                    end
                  end
                end
              end
            end

            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "➕ Create new category...") then
              state.assign_group_plugin = plugin
              state.new_category_input = ""
              state.trigger_open_new_cat_modal = true
            end

            reaper.ImGui_EndMenu(ctx)
          end

          if state.selected_category and state.selected_category ~= "All Categories" then
            local rem_cat = state.selected_category
            local rem_label = (count > 1) and string.format("❌ Remove %d selected from '%s'", count, rem_cat) or string.format("❌ Remove from '%s'", rem_cat)
            if reaper.ImGui_MenuItem(ctx, rem_label) then
              for _, p in ipairs(selected_list) do
                Config.remove_category_from_plugin(p.ident, rem_cat)
                if p.uid then Config.remove_category_from_plugin(p.uid, rem_cat) end
                if p.full_name then Config.remove_category_from_plugin(p.full_name, rem_cat) end

                if p.categories then p.categories[rem_cat] = nil end

                if state and state.plugins then
                  for _, item in ipairs(state.plugins) do
                    if item.ident == p.ident or item.uid == p.uid or item.full_name == p.full_name then
                      if item.categories then item.categories[rem_cat] = nil end
                      if item.category == rem_cat then
                        local next_cat = nil
                        if item.categories then
                          for c in pairs(item.categories) do next_cat = c break end
                        end
                        item.category = next_cat or "Utilities"
                      end
                    end
                  end
                end
              end
            end
          end

          local hide_label = (count > 1) and string.format("👁️ Hide %d selected plugins", count) or "👁️ Hide plugin"
          if reaper.ImGui_MenuItem(ctx, hide_label) then
            for _, p in ipairs(selected_list) do
              Config.hide_plugin(p.ident)
              if p.uid then Config.hide_plugin(p.uid) end
              if p.full_name then Config.hide_plugin(p.full_name) end
              p.is_hidden = true
            end
          end

          reaper.ImGui_Separator(ctx)
          if reaper.ImGui_MenuItem(ctx, "🖼️ Assign custom thumbnail...") then
            state.assign_target_plugin = plugin
            state.custom_thumb_input = plugin.snapshot_path or ""
            state.trigger_open_assign_thumb = true
          end

          if reaper.ImGui_MenuItem(ctx, "📁 Open Snapshot Folder") then
            open_in_explorer(state.snapshot_dirs[1])
          end

          reaper.ImGui_EndPopup(ctx)
        end

        reaper.ImGui_PopStyleColor(ctx, 2)

        -- Draw Card Contents (Image Thumbnail or Fallback Badge)
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        local card_end_x = card_start_x + card_w
        local card_end_y = card_start_y + card_h
        local img_h = card_h - 32

        -- Border
        reaper.ImGui_DrawList_AddRect(draw_list, card_start_x, card_start_y, card_end_x, card_end_y, UITheme.COLORS.CardBorder, 6.0)

        -- Thumbnail texture or Fallback
        local texture = nil
        if plugin.snapshot_path then
          texture = TextureManager.get_texture(ctx, plugin.snapshot_path)
        end

        if texture and (not reaper.APIExists("ImGui_ValidatePtr") or reaper.ImGui_ValidatePtr(texture, "ImGui_Image*")) then
          local box_w = card_w - 8
          local box_h = img_h - 4
          local render_w, render_h = box_w, box_h

          if reaper.APIExists("ImGui_Image_GetSize") then
            local ok, orig_w, orig_h = pcall(reaper.ImGui_Image_GetSize, texture)
            if ok and orig_w and orig_h and orig_w > 0 and orig_h > 0 then
              local img_aspect = orig_w / orig_h
              local box_aspect = box_w / box_h

              if img_aspect > box_aspect then
                render_w = box_w
                render_h = box_w / img_aspect
              else
                render_h = box_h
                render_w = box_h * img_aspect
              end
            end
          end

          -- Center image within box
          local draw_x = card_start_x + 4 + (box_w - render_w) * 0.5
          local draw_y = card_start_y + 4 + (box_h - render_h) * 0.5

          pcall(reaper.ImGui_DrawList_AddImage, draw_list, texture, draw_x, draw_y, draw_x + render_w, draw_y + render_h)
        else
          -- Fallback Card Header with Type Badge
          local badge_col = UITheme.get_badge_color(plugin.type)
          reaper.ImGui_DrawList_AddRectFilled(draw_list, card_start_x + 4, card_start_y + 4, card_start_x + 44, card_start_y + 22, badge_col, 4.0)
          reaper.ImGui_DrawList_AddText(draw_list, card_start_x + 8, card_start_y + 6, UITheme.COLORS.TextPrimary, plugin.type)

          -- Render Vendor name in middle
          reaper.ImGui_DrawList_AddText(draw_list, card_start_x + 8, card_start_y + (img_h / 2) - 6, UITheme.COLORS.TextMuted, plugin.vendor)
        end

        -- Render Plugin Title Footer
        local title_truncated = plugin.name
        if #title_truncated > 18 and card_w < 150 then
          title_truncated = title_truncated:sub(1, 15) .. "..."
        end
        reaper.ImGui_DrawList_AddText(draw_list, card_start_x + 6, card_start_y + img_h + 8, UITheme.COLORS.TextPrimary, title_truncated)

        -- Star indicator if favorited
        if is_fav then
          reaper.ImGui_DrawList_AddText(draw_list, card_end_x - 18, card_start_y + 6, UITheme.COLORS.StarYellow, "★")
        end

        reaper.ImGui_PopID(ctx)
      end
    end

    -- Trigger open popups outside context item scope
    if state.trigger_open_new_cat_modal then
      state.trigger_open_new_cat_modal = nil
      reaper.ImGui_OpenPopup(ctx, "CreateNewCategoryModal")
    end

    if state.trigger_open_assign_thumb then
      state.trigger_open_assign_thumb = nil
      reaper.ImGui_OpenPopup(ctx, "AssignThumbModal")
    end

    if state.trigger_open_no_clipboard_img_popup then
      state.trigger_open_no_clipboard_img_popup = nil
      reaper.ImGui_OpenPopup(ctx, "NoClipboardImageModal")
    end

    -- Create New Category Prompt Modal
    if reaper.ImGui_BeginPopup(ctx, "CreateNewCategoryModal") then
      local selected_list = get_selected_plugin_list(state, filtered)

      reaper.ImGui_TextColored(ctx, UITheme.COLORS.AccentCyan, "➕ Create New Category")
      reaper.ImGui_Separator(ctx)

      reaper.ImGui_Text(ctx, "Enter new category name:")
      reaper.ImGui_PushItemWidth(ctx, 220)
      local changed, val = reaper.ImGui_InputText(ctx, "##NewCatModalInput", state.new_category_input or "")
      if changed then state.new_category_input = val end
      reaper.ImGui_PopItemWidth(ctx)

      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_Button(ctx, "Create & Assign") and state.new_category_input and state.new_category_input:match("%S") then
        local fresh_cat = state.new_category_input:match("^%s*(.-)%s*$")
        Config.add_user_category(fresh_cat)
        
        for _, p in ipairs(selected_list) do
          Config.add_category_to_plugin(p.ident, fresh_cat)
          if p.uid then Config.add_category_to_plugin(p.uid, fresh_cat) end
          if p.full_name then Config.add_category_to_plugin(p.full_name, fresh_cat) end
          
          if not p.categories then p.categories = {} end
          p.categories[fresh_cat] = true
          p.category = fresh_cat

          if state and state.plugins then
            for _, item in ipairs(state.plugins) do
              if item.ident == p.ident or item.uid == p.uid or item.full_name == p.full_name then
                if not item.categories then item.categories = {} end
                item.categories[fresh_cat] = true
                item.category = fresh_cat
              end
            end
          end
        end

        state.new_category_input = ""
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel") then
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_EndPopup(ctx)
    end

    -- No Clipboard Image Alert Popup Modal
    if reaper.ImGui_BeginPopup(ctx, "NoClipboardImageModal") then
      reaper.ImGui_TextColored(ctx, UITheme.COLORS.AccentCyan, "⚠️ No Image in Clipboard")
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Text(ctx, "There is no valid image currently in your system clipboard.")
      reaper.ImGui_Text(ctx, "Copy an image or take a screenshot first, then try again.")
      reaper.ImGui_Separator(ctx)

      if reaper.ImGui_Button(ctx, "OK") then
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_EndPopup(ctx)
    end

    -- Custom Thumbnail Assignment Popup Modal
    if reaper.ImGui_BeginPopup(ctx, "AssignThumbModal") then
      local p = state.assign_target_plugin
      if p then
        reaper.ImGui_TextColored(ctx, UITheme.COLORS.AccentCyan, "Assign Custom Thumbnail")
        reaper.ImGui_Text(ctx, "Plugin: " .. p.name .. " (" .. p.type .. ")")
        reaper.ImGui_Separator(ctx)

        reaper.ImGui_Text(ctx, "Image file path (.png / .jpg):")
        reaper.ImGui_PushItemWidth(ctx, 360)
        local changed, new_path = reaper.ImGui_InputText(ctx, "##ThumbPathInput", state.custom_thumb_input or "")
        if changed then state.custom_thumb_input = new_path end
        reaper.ImGui_PopItemWidth(ctx)

        if reaper.ImGui_Button(ctx, "Save Thumbnail") then
          Config.save_custom_thumbnail(p.ident, state.custom_thumb_input)
          if p.uid then Config.save_custom_thumbnail(p.uid, state.custom_thumb_input) end
          p.snapshot_path = state.custom_thumb_input
          TextureManager.reset()
          reaper.ImGui_CloseCurrentPopup(ctx)
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Clear / Reset") then
          Config.save_custom_thumbnail(p.ident, "")
          if p.uid then Config.save_custom_thumbnail(p.uid, "") end
          p.snapshot_path = nil
          TextureManager.reset()
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
      end
      reaper.ImGui_EndPopup(ctx)
    end

    -- Check if user dropped dragged plugin(s) onto a REAPER track or arrange view
    if (state.dragging_plugin or state.dragging_plugins) and reaper.ImGui_IsMouseReleased(ctx, 0) then
      local mx, my = reaper.GetMousePosition()
      local track, info = reaper.GetTrackFromPoint(mx, my)

      if not track then
        track = create_configured_track()
      end

      local list = state.dragging_plugins or { state.dragging_plugin }
      for _, p in ipairs(list) do
        insert_plugin_to_track(track, p)
      end

      state.dragging_plugin = nil
      state.dragging_plugins = nil
    end

    reaper.ImGui_EndChild(ctx)
  end
end

function UIViews.draw_statusbar(ctx, state)
  local fav_count = 0
  for _, is_fav in pairs(state.favorites) do
    if is_fav then fav_count = fav_count + 1 end
  end

  local sel_count = 0
  if state.selected_plugins then
    for _ in pairs(state.selected_plugins) do
      sel_count = sel_count + 1
    end
  end

  local status_text = string.format("Total Plugins: %d  |  Favorites: %d  |  Selected: %d", 
    #state.plugins, fav_count, sel_count)
  
  reaper.ImGui_TextColored(ctx, UITheme.COLORS.TextMuted, status_text)
end

return UIViews
